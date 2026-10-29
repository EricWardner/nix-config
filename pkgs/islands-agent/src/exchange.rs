//! gcr's secret exchange (`sx-aes-1`), by which a keyring prompter hands
//! back the password typed into it: AES-128-CBC under a key both sides
//! agree by Diffie-Hellman, as key-file text (`[sx-aes-1]` then
//! `public=`, `secret=`, `iv=`, in base64).

use aes::cipher::{BlockEncryptMut as _, KeyIvInit as _, block_padding::Pkcs7};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use num_bigint::BigUint;

const GROUP: &str = "[sx-aes-1]";

/// RFC 3526's 1536-bit MODP group (its generator is 2)
const PRIME: &[u8] = b"FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74\
020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D\
6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5\
AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8\
FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804\
F1746C08CA237327FFFFFFFFFFFFFFFF";
const PRIME_BYTES: usize = 1536 / 8;

fn prime() -> BigUint {
    BigUint::parse_bytes(PRIME, 16).expect("the prime is hex")
}

fn random<const N: usize>() -> [u8; N] {
    let mut bytes = [0; N];
    getrandom::fill(&mut bytes).expect("the kernel has randomness to give");
    bytes
}

/// One prompt's side of the exchange
pub struct Exchange {
    private: BigUint,
    public: BigUint,
    key: Option<[u8; 16]>,
}

impl Exchange {
    pub fn new() -> Self {
        let prime = prime();
        let private = BigUint::from_bytes_be(&random::<PRIME_BYTES>()) % (&prime - 3u32) + 2u32;
        let public = BigUint::from(2u32).modpow(&private, &prime);
        Self {
            private,
            public,
            key: None,
        }
    }

    /// Takes the key from the peer's half; false if it sent none worth having
    pub fn receive(&mut self, text: &str) -> bool {
        if self.key.is_some() {
            return true;
        }
        let prime = prime();
        let Some(peer) = field(text, "public").map(|bytes| BigUint::from_bytes_be(&bytes)) else {
            return false;
        };
        if peer < BigUint::from(2u32) || peer > &prime - 2u32 {
            return false;
        }
        // Padded to the prime's length, as gcr does
        let shared = peer.modpow(&self.private, &prime).to_bytes_be();
        let mut ikm = vec![0; PRIME_BYTES - shared.len()];
        ikm.extend(shared);
        let mut key = [0; 16];
        hkdf::Hkdf::<sha2::Sha256>::new(None, &ikm)
            .expand(&[], &mut key)
            .expect("16 bytes is a length HKDF gives");
        self.key = Some(key);
        true
    }

    /// Our half, with the secret if there is one (and a key to hide it with)
    pub fn send(&self, secret: Option<&str>) -> String {
        let mut text = format!(
            "{GROUP}\npublic={}\n",
            BASE64.encode(self.public.to_bytes_be())
        );
        if let (Some(secret), Some(key)) = (secret, self.key) {
            let iv = random::<16>();
            let mut buffer = secret.as_bytes().to_vec();
            buffer.resize(secret.len() / 16 * 16 + 16, 0);
            let encrypted = cbc::Encryptor::<aes::Aes128>::new(&key.into(), &iv.into())
                .encrypt_padded_mut::<Pkcs7>(&mut buffer, secret.len())
                .expect("the buffer has room for the padding");
            text += &format!(
                "secret={}\niv={}\n",
                BASE64.encode(encrypted),
                BASE64.encode(iv)
            );
        }
        text
    }
}

/// A base64 field from the exchange's group
fn field(text: &str, name: &str) -> Option<Vec<u8>> {
    text.lines()
        .map(str::trim)
        .skip_while(|line| *line != GROUP)
        .skip(1)
        .take_while(|line| !line.starts_with('['))
        .filter_map(|line| line.split_once('='))
        .find(|(key, _)| key.trim() == name)
        .and_then(|(_, value)| BASE64.decode(value.trim()).ok())
}

#[cfg(test)]
mod tests {
    use super::*;
    use aes::cipher::BlockDecryptMut as _;

    #[test]
    fn both_sides_agree_and_the_secret_comes_through() {
        let mut prompter = Exchange::new();
        let mut client = Exchange::new();
        assert!(client.receive(&prompter.send(None)));
        assert!(prompter.receive(&client.send(None)));
        assert_eq!(prompter.key, client.key);

        let sent = prompter.send(Some("hunter2 but longer than a block"));
        let mut secret = field(&sent, "secret").unwrap();
        let iv: [u8; 16] = field(&sent, "iv").unwrap().try_into().unwrap();
        let plain = cbc::Decryptor::<aes::Aes128>::new(&client.key.unwrap().into(), &iv.into())
            .decrypt_padded_mut::<Pkcs7>(&mut secret)
            .unwrap();
        assert_eq!(plain, b"hunter2 but longer than a block");
    }

    #[test]
    fn a_peer_without_a_public_key_is_turned_away() {
        assert!(!Exchange::new().receive("[sx-aes-1]\n"));
        assert!(!Exchange::new().receive("[sx-aes-1]\npublic=AQ==\n"));
    }
}
