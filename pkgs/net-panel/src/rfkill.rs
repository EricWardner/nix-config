//! Airplane mode through /dev/rfkill (logind's uaccess rule makes it
//! writable for the seat's user): every radio blocked is airplane mode, and
//! toggling blocks or unblocks them all at once, Bluetooth included.

use std::cell::RefCell;
use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{Read as _, Write as _};
use std::rc::Rc;

use async_channel::Sender;

use crate::Event;

const DEVICE: &str = "/dev/rfkill";
// struct rfkill_event: idx u32, type u8, op u8, soft u8, hard u8. Newer
// kernels append a byte, which a read of 8 simply leaves off.
const EVENT_SIZE: usize = 8;
const TYPE_ALL: u8 = 0;
const OP_DEL: u8 = 1;
const OP_CHANGE_ALL: u8 = 3;

pub struct Rfkill {
    writer: RefCell<File>,
}

impl Rfkill {
    /// Sends `Event::Airplane` at start and whenever it changes. Reads block,
    /// so they run on their own thread; the kernel starts each reader with an
    /// event per radio.
    pub fn watch(tx: Sender<Event>) -> std::io::Result<Rc<Self>> {
        let mut reader = File::open(DEVICE)?;
        let writer = OpenOptions::new().write(true).open(DEVICE)?;
        std::thread::spawn(move || {
            let mut blocked: HashMap<u32, bool> = HashMap::new();
            let mut last = None;
            let mut event = [0u8; EVENT_SIZE];
            while reader.read_exact(&mut event).is_ok() {
                let idx = u32::from_ne_bytes([event[0], event[1], event[2], event[3]]);
                if event[5] == OP_DEL {
                    blocked.remove(&idx);
                } else {
                    blocked.insert(idx, event[6] != 0 || event[7] != 0);
                }
                let airplane = !blocked.is_empty() && blocked.values().all(|b| *b);
                if last != Some(airplane) {
                    last = Some(airplane);
                    if tx.send_blocking(Event::Airplane(airplane)).is_err() {
                        break;
                    }
                }
            }
        });
        Ok(Rc::new(Self {
            writer: RefCell::new(writer),
        }))
    }

    pub fn set_airplane(&self, on: bool) -> std::io::Result<()> {
        let event = [0, 0, 0, 0, TYPE_ALL, OP_CHANGE_ALL, u8::from(on), 0];
        self.writer.borrow_mut().write_all(&event)
    }
}
