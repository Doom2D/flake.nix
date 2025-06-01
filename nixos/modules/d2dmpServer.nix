{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.d2dmp;

  xorgDisplayNumber = "53";
  userDir = "/var/lib/d2dmp";
  user = "d2dmultiplayer";
  group = "d2dmultiplayer";

  updated_exe = pkgs.fetchurl {
    url = "https://github.com/polybluez/filedump/releases/download/Tag2/130_sv_but_with_synctype_fix.exe";
    sha256 = "sha256-CsqA1rOkvjQX5iapc8okwreVN7o5n9L6VDCb4j4BqxE=";
  };
in {
  options.services.d2dmp = {
    enable = (lib.mkEnableOption "Doom2D Multiplayer servers") // {default = true;};
    wine = lib.mkPackageOption pkgs "wineWow64Packages.stable" {};
    dataPackage = lib.mkPackageOption pkgs "doom2d-multiplayer-game-data" {};
    swiftshaderD3d8Dll = lib.mkOption {
      default = null;
      type = lib.types.path;
      description = ''
        Swiftshader software render d3d8 dll.
      '';
    };
    openFirewall = (lib.mkEnableOption "Doom2D Multiplayer servers") // {default = true;};
    settings = lib.mkOption {
      description = ''
        Generates the `server.cfg` file.
      '';

      default = {};

      type = lib.types.submodule {
        freeformType = with lib.types; let
          scalars = oneOf [singleLineStr int float];
        in
          attrsOf (oneOf [scalars (nonEmptyListOf scalars)]);
      };
    };
    autoexec = lib.mkOption {
      description = ''
        Generates the `autoexec.cfg` file. Commands from this file will be run at a new round.
      '';

      default = "";
      type = lib.types.lines;
    };
  };

  config = let
    mkServerService = name: let
      isOnLowerPort = cfg.settings.sv_port < 1024;

      usageLimitAttrs = {
        CPUAccounting = true;
        MemoryAccounting = true;
        MemoryHigh = 92 * 1024 * 1024;
        MemoryMax = 150 * 1024 * 1024;
        TasksAccounting = true;
        IOAccounting = true;
      };

      hardeningAttrs = {
        NoNewPrivileges = true;
        DevicePolicy = "closed";
        ProtectSystem = true;
        ProtectHome = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ProtectKernelLogs = true;
        PrivateMounts = true;
        ProtectHostname = true;
        PrivateTmp = true;
        # breaks CAP_NET_BIND_SERVICE if enabled
        PrivateUsers = !isOnLowerPort;
        #TemporaryFileSystem = "/:ro";
        #BindPaths = baseDir;
        #BindReadOnlyPaths = doom2df-data;
        # Net
        SecureBits = lib.optionalString isOnLowerPort "keep-caps";
        AmbientCapabilities = lib.optionals isOnLowerPort ["CAP_NET_BIND_SERVICE" "CAP_NET_ADMIN"];
        CapabilityBoundingSet = lib.optionals isOnLowerPort ["CAP_NET_BIND_SERVICE" "CAP_NET_ADMIN"];
        SocketBindDeny = "any";
        SocketBindAllow = ["tcp:${builtins.toString cfg.settings.sv_port}"];
      };
    in {
      description = "Doom2D Multiplayer server instance '${name}'";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "${xdummyServiceName}.service"];
      requires = ["network.target" "${xdummyServiceName}.service"];
      path = [cfg.wine pkgs.xdotool pkgs.xorg.xwininfo pkgs.gawk];
      environment = {
        WINEPREFIX = "${userDir}/wine";
        XDG_RUNTIME_DIR = "${userDir}/tmp";
        HOME = "${userDir}/tmp";
        DISPLAY = ":${xorgDisplayNumber}";
        WINEDLLOVERRIDES = "d3d8=n;winemenubuilder.exe=d;mscoree,mshtml=";
        WINEDEBUG="-all";
      };
      serviceConfig =
        {
          #              StandardOutput = "null";
          #              StandardError = "null";
          User = user;
          Group = user;
          LogFilterPatterns = [
          ];
          # Restart every 6 hours, because the game server will die over time.
          Restart = "always";
          RuntimeMaxSec = "6h";

          ExecStart = script userDir;
        }
        // hardeningAttrs
        // usageLimitAttrs;
    };

    mkXdummyService = let
      inherit (pkgs) writeText xorg writeShellScriptBin;
      megabytes = bytes: builtins.toString (builtins.ceil (bytes * 1000));
      xorgConfig = writeText "dummy-xorg.conf" ''
        Section "ServerLayout"
          Identifier     "dummy_layout"
          Screen         0 "dummy_screen"
          InputDevice    "dummy_keyboard" "CoreKeyboard"
          InputDevice    "dummy_mouse" "CorePointer"
        EndSection

        Section "ServerFlags"
          Option "DontVTSwitch" "true"
          Option "AllowMouseOpenFail" "true"
          Option "PciForceNone" "true"
          Option "AutoEnableDevices" "false"
          Option "AutoAddDevices" "false"
        EndSection

        Section "Files"
          ModulePath "${xorg.xorgserver.out}/lib/xorg/modules"
          ModulePath "${xorg.xf86videodummy}/lib/xorg/modules"
        EndSection

        Section "Module"
          Load           "glx"
        EndSection

        Section "InputDevice"
          Identifier     "dummy_mouse"
          Driver         "void"
        EndSection

        Section "InputDevice"
          Identifier     "dummy_keyboard"
          Driver         "void"
        EndSection

        Section "Monitor"
          Identifier     "dummy_monitor"
          HorizSync       30.0 - 130.0
          VertRefresh     50.0 - 250.0
          Option         "DPMS"
        EndSection

        Section "Device"
          Identifier     "dummy_device"
          Driver         "dummy"
          VideoRam       ${megabytes 1}
        EndSection

        Section "Screen"
          Identifier     "dummy_screen"
          Device         "dummy_device"
          Monitor        "dummy_monitor"
          DefaultDepth    24
          SubSection     "Display"
            Depth       24
            Modes      "1x1"
          EndSubSection
        EndSection
      '';
      xdummy = writeShellScriptBin "xdummy" ''
        exec ${xorg.xorgserver.out}/bin/Xorg \
          -noreset \
          -logfile /dev/null \
          "$@" \
          -config "${xorgConfig}"
      '';
    in {
      description = "Xdummy server for Doom2D Multiplayer game servers";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig =
        {
          ExecStart = ''
            ${xdummy}/bin/xdummy :${xorgDisplayNumber} +extension GLX
          '';
        }
        // {
          CPUAccounting = true;
          MemoryAccounting = true;
          MemoryHigh = 8 * 1024 * 1024;
          MemoryMax = 16 * 1024 * 1024;
          TasksAccounting = true;
          IOAccounting = true;
        };
    };

    printSettings = settingsAttr:
      builtins.concatStringsSep "\n" (
        lib.mapAttrsToList (
          key: option: let
            escape = s: lib.replaceStrings ["\""] ["'"] s;
            quote = s: "${s}";

            toValue = x: let
              quoteFunc =
                if lib.typeOf x == "int" || builtins.typeOf x == "float"
                then lib.id
                else quote;
            in
              quoteFunc (escape (toString x));

            value = (
              if lib.isList option
              then
                builtins.concatStringsSep
                ","
                (builtins.map (x: toValue x) option)
              else toValue option
            );
          in "${key} ${value}"
        )
        settingsAttr
      );
    script = userDir: let
      exe = "130_sv_but_with_synctype_fix.exe";
      configFile = let
        src = pkgs.writeText "${abbr}-server.cfg" (printSettings cfg.settings);
        converted = convertToWin1251 src;
      in
        converted;
      autoExec = let
        src = pkgs.writeText "${abbr}-autoexec.cfg" cfg.autoexec;
        converted = convertToWin1251 src;
      in
        converted;
      launchCmd = "wine ${userDir}/${exe} -nogui -q";
      convertToWin1251 = x: let
        drv =
          pkgs.runCommandLocal "win1251-convert" {
            nativeBuildInputs = [pkgs.iconv pkgs.coreutils];
          } ''
            mkdir -p $out
            iconv -f UTF-8 -t WINDOWS-1251 -o "$out/str" ${x}
          '';
      in
        drv;
      closeErrorWindowScript =
        pkgs.writeShellScript "close-d2dmp-error-window"
        ''
          while true; do
              sleep 10s;
              xdotool key enter;
              sleep 10s;
          done
        '';
    in
      # nix-store -q --referrers-closure /nix/store/dp2c6lh3mj8kx1l1520ackwjw8y9r400-gtk4-4.16.3/
      pkgs.writeShellScript "d2dmp-run"
      (
        ''
          mkdir -p "${userDir}/wine" "${userDir}/tmp"
          cd "${userDir}"
          cp ${dataPackage}/* "${userDir}" -r
          cp "${updated_exe}" ${exe}
          cp "${cfg.swiftshaderD3d8Dll}" "${userDir}/d3d8.dll"
          chmod 700 -R ${userDir}
        ''
        + ''
          rm ${userDir}/data/cfg/autoexec.cfg
          cat "${autoExec}/str" > "${userDir}/data/cfg/autoexec.cfg"

          rm ${userDir}/data/cfg/server.cfg
          cat "${configFile}/str" > "${userDir}/data/cfg/server.cfg"
        ''
        # Workaround for server getting stuck at "getting external IP" stage
        # If you set sv_lan 1 and launch the server, it won't try to get its own IP
        # But it won't sync with master. To fix that, set sv_lan 0 in `autoexec.cfg` and `resync`.
        # Thanks to BlackDoomer!
        + ''
          echo -e "\nsv_lan 1\n" >> "${userDir}/data/cfg/server.cfg"
          echo -e "\nsv_lan 0\nresync\n" >> "${userDir}/data/cfg/autoexec.cfg"
        ''
        # Backup old logs.
        + ''
          [[ -f ${userDir}/data/logs/server.log ]] && cp --backup=t ${userDir}/data/logs/server.log ${userDir}/data/logs/server.old.log
        ''
        # First, initialize the prefix. Unset DISPLAY so that WINE doesn't offer to install Mono and other things with a graphical dialog.
        # Then, disable showing crash dialog and kill wineserver.
        # Finally, try to launch the server.
        + ''
          (
          unset DISPLAY;
          wineboot -i
          wine regedit ${pkgs.writeText "no-crashdialog.reg" ''
            [HKEY_CURRENT_USER\Software\Wine\WineDbg]
            "ShowCrashDialog"=dword:00000000
          ''};
          wineboot -r -f
          wineserver -k
          )
          ${closeErrorWindowScript} &
          ${launchCmd}
        ''
      );
    abbr = "d2dmp";
    name = "deathmatch";
    serverServiceName = "${abbr}-${name}";
    xdummyServiceName = "${abbr}-xdummy";
    dataPackage = cfg.dataPackage;
  in
    lib.mkIf cfg.enable {
      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
        cfg.settings.sv_port
      ];
      users.users."${user}" = {
        description = "Doom2D Multiplayer service user";
        isSystemUser = true;
        inherit group;
      };
      users.groups."${group}" = {};
      systemd.services."${xdummyServiceName}" = mkXdummyService;
      systemd.services."${serverServiceName}" = mkServerService name;
      systemd.tmpfiles.rules = [
        # Recursively change owner to Doom2D Forever service user
        "d '${userDir}' 0700 ${user} ${group} - -"
        "Z '${userDir}' 0700 ${user} ${group} - -"
      ];
    };
}
