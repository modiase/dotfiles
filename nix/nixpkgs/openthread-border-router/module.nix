{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.services.openthread-border-router;
  package = pkgs.callPackage ./package.nix {
    cpcd = if cfg.cpcSupport.enable then cfg.cpcSupport.package else null;
  };
  logLevelMappings = {
    "emerg" = 0;
    "alert" = 1;
    "crit" = 2;
    "err" = 3;
    "warning" = 4;
    "notice" = 5;
    "info" = 6;
    "debug" = 7;
  };
  logLevel = lib.getAttr cfg.logLevel logLevelMappings;
in
{
  options.services.openthread-border-router = {
    enable = lib.mkEnableOption "the OpenThread Border Router";

    cpcSupport = {
      enable = lib.mkEnableOption "CPC (Co-Processor Communication) support for spinel+cpc:// URLs";
      package = lib.mkOption {
        type = lib.types.package;
        description = "The cpcd package providing libcpc";
      };
    };

    backboneInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "The network interface on which to advertise the thread ipv6 mesh prefix";
    };

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "wpan0";
      description = "The network interface to create for thread packets";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum (lib.attrNames logLevelMappings);
      default = "err";
      description = "The level to use when logging messages";
    };

    rest = {
      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "The address on which to listen for REST API requests";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = "The port on which to listen for REST API requests";
      };
    };

    web = {
      enable = lib.mkEnableOption "the web interface";
      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "The address on which the web interface should listen";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 8082;
        description = "The port on which the web interface should listen";
      };
    };

    radio = {
      device = lib.mkOption {
        type = lib.types.path;
        description = "The device path of the radio";
      };

      baudRate = lib.mkOption {
        type = lib.types.int;
        default = 460800;
        description = "The baud rate of the radio device";
      };

      flowControl = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable hardware flow control";
      };

      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The URL of the radio device (overrides device/baudRate/flowControl)";
      };

      extraDevices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra devices to add to the radio device";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.openthread-border-router.radio.url = lib.mkDefault (
      "spinel+hdlc+uart://${cfg.radio.device}?"
      + lib.concatStringsSep "&" (
        [ "uart-baudrate=${toString cfg.radio.baudRate}" ]
        ++ lib.optional cfg.radio.flowControl "uart-flow-control"
      )
    );

    environment.systemPackages = [ package ];

    networking.enableIPv6 = true;
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.${cfg.backboneInterface}.accept_ra" = 2;
      "net.ipv6.conf.${cfg.backboneInterface}.accept_ra_rt_info_max_plen" = 64;
    };

    services.avahi = {
      enable = lib.mkDefault true;
      publish = {
        enable = lib.mkDefault true;
        userServices = lib.mkDefault true;
      };
    };

    systemd.services.otbr-agent = {
      description = "OpenThread Border Router Agent";
      wantedBy = [ "multi-user.target" ];
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        THREAD_IF = cfg.interfaceName;
      };
      serviceConfig = {
        ExecStartPre = "${lib.getExe' package "otbr-firewall"} start";
        ExecStart = lib.concatStringsSep " " (
          [
            (lib.getExe' package "otbr-agent")
            "--verbose"
            "--backbone-ifname ${cfg.backboneInterface}"
            "--thread-ifname ${cfg.interfaceName}"
            "--debug-level ${toString logLevel}"
            "--rest-listen-port ${toString cfg.rest.listenPort}"
            "--rest-listen-address ${cfg.rest.listenAddress}"
            cfg.radio.url
          ]
          ++ cfg.radio.extraDevices
        );
        ExecStopPost = "${lib.getExe' package "otbr-firewall"} stop";
        KillMode = "mixed";
        Restart = "on-failure";
        RestartSec = 5;
        RestartPreventExitStatus = "SIGKILL";
        StateDirectory = "thread";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
      };
      path = [
        pkgs.ipset
        pkgs.iptables
      ];
    };

    systemd.services.otbr-web = lib.mkIf cfg.web.enable {
      description = "OpenThread Border Router Web Interface";
      after = [ "otbr-agent.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe' package "otbr-web")
          "-I ${cfg.interfaceName}"
          "-d ${toString logLevel}"
          "-a ${cfg.web.listenAddress}"
          "-p ${toString cfg.web.listenPort}"
        ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelLogs = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        CapabilityBoundingSet = "";
      };
    };
  };
}
