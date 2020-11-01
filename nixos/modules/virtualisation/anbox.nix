{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.virtualisation.anbox;
  kernelPackages = config.boot.kernelPackages;
  useAnboxModules = kernelPackages.kernelOlder "5.0";
  addrOpts = v: addr: pref: name: {
    address = mkOption {
      default = addr;
      type = types.str;
      description = ''
        IPv${toString v} ${name} address.
      '';
    };

    prefixLength = mkOption {
      default = pref;
      type = types.addCheck types.int (n: n >= 0 && n <= (if v == 4 then 32 else 128));
      description = ''
        Subnet mask of the ${name} address, specified as the number of
        bits in the prefix (<literal>${if v == 4 then "24" else "64"}</literal>).
      '';
    };
  };

in

{

  options.virtualisation.anbox = {

    enable = mkEnableOption "Anbox";

    image = mkOption {
      default = pkgs.anbox.image;
      example = literalExample "pkgs.anbox.image";
      type = types.package;
      description = ''
        Base android image for Anbox.
      '';
    };

    extraInit = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra shell commands to be run inside the container image during init.
      '';
    };

    ipv4 = {
      container = addrOpts 4 "192.168.250.2" 24 "Container";
      gateway = addrOpts 4 "192.168.250.1" 24 "Host";

      dns = mkOption {
        default = "1.1.1.1";
        type = types.str;
        description = ''
          Container DNS server.
        '';
      };
    };
  };

  config = mkIf cfg.enable {

    assertions = singleton {
      assertion = versionAtLeast (getVersion config.boot.kernelPackages.kernel) "4.18";
      message = "Anbox needs user namespace support to work properly";
    };

    environment.systemPackages = with pkgs; [ anbox ];

    # Mainline ashmem/binder drivers not available as modules
    boot.kernelModules = optionals useAnboxModules [ "ashmem_linux" "binder_linux" ];
    boot.extraModulePackages = optional useAnboxModules kernelPackages.anbox;

    systemd.mounts = optional (!useAnboxModules) {
      requiredBy = [ "anbox-container-manager.service" ];
      description = "Anbox Binder File System";
      what = "binder";
      where = "/dev/binderfs";
      type = "binder";
    };

    virtualisation.lxc.enable = true;
    networking.bridges.anbox0.interfaces = [];
    networking.interfaces.anbox0.ipv4.addresses = [ cfg.ipv4.gateway ];

    networking.nat = {
      enable = true;
      internalInterfaces = [ "anbox0" ];
    };

    systemd.services.anbox-container-manager = let
      anboxloc = "/var/lib/anbox";
    in {
      description = "Anbox Container Management Daemon";

      environment.XDG_RUNTIME_DIR="${anboxloc}";

      wantedBy = [ "multi-user.target" ];
      preStart = let
        initsh = pkgs.writeText "nixos-init" (''
          #!/system/bin/sh
          setprop nixos.version ${config.system.nixos.version}

          # we don't have radio
          setprop ro.radio.noril yes
          stop ril-daemon

          # speed up boot
          setprop debug.sf.nobootanimation 1
        '' + cfg.extraInit);
        initshloc = "${anboxloc}/rootfs-overlay/system/etc/init.goldfish.sh";
      in ''
        mkdir -p ${anboxloc}
        mkdir -p $(dirname ${initshloc})
        [ -f ${initshloc} ] && rm ${initshloc}
        cp ${initsh} ${initshloc}
        chown 100000:100000 ${initshloc}
        chmod +x ${initshloc}
      '';

      serviceConfig = {
        ExecStart = ''
          ${pkgs.anbox}/bin/anbox container-manager \
            --data-path=${anboxloc} \
            --android-image=${cfg.image} \
            --container-network-address=${cfg.ipv4.container.address} \
            --container-network-gateway=${cfg.ipv4.gateway.address} \
            --container-network-dns-servers=${cfg.ipv4.dns} \
            --use-rootfs-overlay \
            --privileged \
            --daemon
        '';
      };
    };
  };

}
