{
  config,
  lib,
  user,
  ...
}:
with lib;
let
  cfg = config.modules.virtualization;
in
{
  options = {
    modules.virtualization.enable = mkEnableOption "Enable virtualization" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    users = {
      users.${user.username} = {
        extraGroups = mkAfter [
          "docker"
        ];
      };
    };

    virtualisation = {
      docker.enable = true;
      docker.daemon.settings = {
        # Default bridge parked in the last /24 of the primary pool so it
        # doesn't fragment it (its route existing makes the allocator skip it).
        bip = "172.31.255.1/24";
        # Pools spread across all three RFC 1918 families, because Docker
        # skips any candidate subnet that overlaps an existing route: a
        # single hostile LAN or VPN can shadow one family (a Wi-Fi network
        # handing out 10.x/8 masks blocked the entire previous 10.201.0.0/16
        # pool), but not all three. Docker walks this list in order.
        #
        # Deliberately NOT 100.64.0.0/10 (CGN space), despite it being the
        # most collision-free range: it is not RFC 1918, and software that
        # derives identity from "my private IP" rejects it — Zitadel's
        # sonyflake machine-ID panicked at boot on a 100.64.x address
        # ("no private ip address"). Container networks must look private
        # to the software running on them.
        default-address-pools = [
          {
            # Top of 172.16/12 — corp VPNs usually take the low end. (AWS
            # default VPCs use 172.31; relevant only if a VPN routes one.)
            base = "172.31.0.0/16";
            size = 24;
          }
          {
            # High 192.168 — consumer routers squat the low end (0/1/86.x).
            base = "192.168.240.0/20";
            size = 24;
          }
          {
            # The old pool, kept as last resort — dead on /8-mask networks
            # like the one that prompted this list, fine everywhere else.
            base = "10.201.0.0/16";
            size = 24;
          }
        ];
      };

      containers.enable = true;
    };
  };
}
