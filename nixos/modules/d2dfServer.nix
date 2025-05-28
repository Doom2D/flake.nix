{
  config,
  lib,
  pkgs,
  ...
}: let
  createMapsListSrc = mapsJsonPath: {
    # perWad, perMap
    generateMode ? "perMap",
  }:
    pkgs.writeText "d2df-maplist-generator.mjs" ''
      import { promises as fs } from "fs"

      // https://stackoverflow.com/questions/521295/seeding-the-random-number-generator-in-javascript
      function cyrb128(str) {
          let h1 = 1779033703, h2 = 3144134277,
              h3 = 1013904242, h4 = 2773480762;
          for (let i = 0, k; i < str.length; i++) {
              k = str.charCodeAt(i);
              h1 = h2 ^ Math.imul(h1 ^ k, 597399067);
              h2 = h3 ^ Math.imul(h2 ^ k, 2869860233);
              h3 = h4 ^ Math.imul(h3 ^ k, 951274213);
              h4 = h1 ^ Math.imul(h4 ^ k, 2716044179);
          }
          h1 = Math.imul(h3 ^ (h1 >>> 18), 597399067);
          h2 = Math.imul(h4 ^ (h2 >>> 22), 2869860233);
          h3 = Math.imul(h1 ^ (h3 >>> 17), 951274213);
          h4 = Math.imul(h2 ^ (h4 >>> 19), 2716044179);
          h1 ^= (h2 ^ h3 ^ h4), h2 ^= h1, h3 ^= h1, h4 ^= h1;
          return [h1>>>0, h2>>>0, h3>>>0, h4>>>0];
      }
      // Side note: Only designed & tested for seed generation,
      // may be suboptimal as a general 128-bit hash.

      function sfc32(a, b, c, d) {
        return function() {
          a |= 0; b |= 0; c |= 0; d |= 0;
          let t = (a + b | 0) + d | 0;
          d = d + 1 | 0;
          a = b ^ b >>> 9;
          b = c + (c << 3) | 0;
          c = (c << 21 | c >>> 11);
          c = c + t | 0;
          return (t >>> 0) / 4294967296;
        }
      }

      const shuffled = array => {
          return array.slice()
            .map(value => ({ value, sort: (function () {
              let seed = cyrb128((new Date().getTime() + Math.random()).toString());
              return (sfc32(seed[0], seed[1], seed[2], seed[3]))()
            })()}))
            .sort((a, b) => a.sort - b.sort)
            .map(({ value }) => value)
      }

      const path = "${mapsJsonPath}"

      const duplicateArr = (mode, x) => {
          const shuffleNested = (times, x) => {
              return x.map((value, index) => {
                let el = value.slice()
                for (let i = 0; i < times; i += 1) {
                  el = shuffled(el)
                }
                return el
              })
          }
          let flat = undefined
          if (mode == "wad") {
              flat = x.flat()
          } else if (mode == "map") {
              const converted = x.map((v, i) => v.maps.map((vp, ip) => {
                  return {
                      source: v.source,
                      map: vp
                  }
              }))
              flat = converted.flat()
          } else {
              throw new Error("What")
          }
          const cycles = 1
          // Seed the random number generator with datetime
          let seed = cyrb128((new Date().getTime() + Math.random()).toString());
          const shuffleTimes = ((sfc32(seed[0], seed[1], seed[2], seed[3]))()) * (10*1000)
          const replicated = Array(cycles).fill(flat.slice())
          const input = shuffleNested(shuffleTimes, replicated).flat()
          return input
      };

      const createAliasPerWad = (formatAlias, wadsArr) => wadsArr.reduce((prev, cur, index, arr) => {
          let val = "";
          const baseName = "coop";
          const lastElemIndex = arr.length - 1;
          const source = cur.source;
          const map = cur.entry;
          if (index == lastElemIndex) {
              const nextElemIndex = 0;
              const middleElemIndex = Math.floor(arr.length / 2)
              const middleElem = arr[middleElemIndex]
              const firstElemIndex = 0
              //val = formatAlias(baseName, index, nextElemIndex, source, map) + `\ncall dm''${nextElemIndex}\nmap ''${middleElem.source} ''${middleElem.entry}`
              val = formatAlias(baseName, index, nextElemIndex, source, map) + `\ncall ''${baseName}''${firstElemIndex}\nendmap`
          }
          else {
              const nextElemIndex = index + 1;
              val = formatAlias(baseName, index, nextElemIndex, source, map)
          };
          return `''${prev}\n''${val}`
      }, "")

      const createAliasPerMap = (formatAlias, mapsArr) => mapsArr.reduce((prev, cur, index, arr) => {
          let val = "";
          const baseName = "dm";
          const lastElemIndex = arr.length - 1;
          const source = cur.source;
          const map = cur.map;
          if (index == lastElemIndex) {
              const nextElemIndex = 0;
              const middleElemIndex = Math.floor(arr.length / 2)
              const middleElem = arr[middleElemIndex]
              val = formatAlias(baseName, index, nextElemIndex, source, map) + `\ncall dm''${nextElemIndex}\nmap ''${middleElem.source} ''${middleElem.map}`
          }
          else {
              const nextElemIndex = index + 1;
              val = formatAlias(baseName, index, nextElemIndex, source, map)
          };
          return `''${prev}\n''${val}`
      }, "")

      const perMap = (data) => {
          const formatAlias = (baseName, index, nextElemIndex, source, map) => `alias ''${baseName}''${index} "event onmapstart nextmap ''${source} ''${map}; event onmapend call ''${baseName}''${nextElemIndex}"`
          // if totalLen > 0
          const final = createAliasPerMap(formatAlias, duplicateArr("map", data))
          return final
      }

      const perWad = (data) => {
          const formatAlias = (baseName, index, nextElemIndex, source, entry) =>
            `alias ''${baseName}''${index} "nextmap megawads/''${source} ''${entry}; event onwadend call ''${baseName}''${nextElemIndex}"`
          // if totalLen > 0
          const final = createAliasPerWad(formatAlias, duplicateArr("wad", data))
          return final
      }

      const data = await fs.readFile(path)
      const json = JSON.parse(data)
      const list = ${generateMode}(json)
      console.log(list)
    '';
in {
  options.services.d2df = {
    enable = (lib.mkEnableOption "Doom2D Forever servers") // {default = true;};
    openFirewall = (lib.mkEnableOption "open firewall ports") // {default = true;};
    servers = lib.mkOption {
      default = {};
      description = ''
        Each attribute of this option defines a systemd service that
        runs a Doom 2D Forever server. The name of each systemd service is
        `d2df-«name».service`,
        where «name» is the corresponding
        attribute name.
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = (lib.mkEnableOption "this doom2d server") // {default = true;};
          package = lib.mkPackageOption pkgs "doom2d-forever" {};
          assets = lib.mkOption {
            type = lib.types.path;
            description = ''
              Assets path, has {game,standart,shrshade,doomer,doom2d}.wad and {botlist,botnames}.txt
            '';
          };
          name = lib.mkOption {
            type = lib.mkOptionType {
              name = "d2dfServerName";
              description = "Doom 2D Forever server name";
              descriptionClass = "noun";
              check = x: lib.types.nonEmptyStr.check x && lib.stringLength x <= 64;
            };
            default = "Doom 2D Forever server";
            description = ''
              Name of the server which will be shown in the server list.
            '';
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 25666;
            description = ''
              Port the server will listen on.
            '';
          };
          ping = lib.mkEnableOption "pinging of this server in masterserver";
          maxPlayers = lib.mkOption {
            type = lib.types.int;
            default = 24;
            description = ''
              The amount of slots to reserve for players.
            '';
          };
          order = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = ''
              Order in which the server should start.
            '';
          };
          gameMode = lib.mkOption {
            type = lib.types.enum ["dm" "coop" "pubg" "defrag" "duel"];
            description = ''
              The game type to use on the server.
            '';
          };
          rcon = {
            enable = lib.mkEnableOption "rcon access";
            file = lib.mkOption {
              type = lib.types.path;
              description = ''
                Path to file from which RCON password will be read from.
              '';
            };
          };
          logs = {
            enable = lib.mkEnableOption "logs" // {default = true;};
            filterMessages = lib.mkEnableOption "filter unimportant messages";
          };
          mapsJson = lib.mkOption {
            type = lib.types.path;
            description = ''
              Path to the JSON file with the maplist.
            '';
          };

          bots = {
            enable = lib.mkEnableOption "bots on this server";
            count = lib.mkOption {
              type = lib.types.int;
              default = 0;
              description = ''
                Amount of bots to be added when the server starts.
              '';
            };

            # TODO make this have effect
            allowKick = lib.mkEnableOption "the ability for players to kick bots";

            # TODO make this have effect
            fillEmptyPlayerSlots = lib.mkEnableOption "bots filling empty player slots";
          };

          # Certain changes need to happen at the beginning of the file.
          prependConfig = lib.mkOption {
            type = with lib.types; nullOr lines;
            default = null;
            description = ''
              Literal text to insert at the start of `server.cfg`.
            '';
          };

          settings = lib.mkOption {
            description = ''
              Generates the `server.cfg` file. Refer to [upstream's example][0] for
              details.

              [0]: https://repo.or.cz/d2df-sdl.git/blob/refs/heads/master:/man/en/d2df.3.txt
            '';

            default = {};

            type = lib.types.submodule {
              freeformType = with lib.types; let
                scalars = oneOf [singleLineStr int float];
              in
                attrsOf (oneOf [scalars (nonEmptyListOf scalars)]);

              options.net_master_list = lib.mkOption {
                type = lib.types.listOf lib.types.singleLineStr;
                default = ["mpms.doom2d.org:25665"];
                description = ''
                  Masterservers which will be used to advertise this server's existence.
                '';
              };
            };
          };

          appendConfig = lib.mkOption {
            type = with lib.types; nullOr lines;
            default = null;
            description = ''
              Literal text to insert at the end of `server.cfg`.
            '';
          };

          execStart = lib.mkOption {
            type = with lib.types; nullOr lines;
            default = null;
            description = ''
              Commands to be executed when the server starts.
            '';
          };
        };
      });
    };
  };

  config = let
    cfg = config.services.d2df;
    user = "d2dforever";
    abbr = "d2df";
    baseDir = "/var/lib/${abbr}";
    startScriptName = name: "${abbr}-${name}-start";
    serviceName = name: "${abbr}-${name}";
    timerName = name: "restart_nightly_${serviceName name}";
    socketName = name: "${serviceName name}.socket";
  in
    lib.mkIf cfg.enable (let
      doom2df-dm-maps-tarball = pkgs.fetchzip {
        name = "doom2df-dm-maps-tarball";
        url = "https://github.com/polybluez/filedump/releases/download/Tag3/dfmaps.tar.xz";
        sha256 = "sha256-Coeeacqo8WYcB2OqJefEeOx3/rBvHvY9/CSE8lgfYGI=";
        stripRoot = false;
      };
      doom2df-dm-maps = pkgs.stdenv.mkDerivation {
        name = "doom2df-dm-maps";
        nativeBuildInputs = [pkgs.findutils pkgs.coreutils];
        src = doom2df-dm-maps-tarball;
        installPhase = ''
          mkdir -p $out/maps
          find "${doom2df-dm-maps-tarball}/df/processed"  -type f -exec ln -s {} $out/maps \;
          [[ -f "$out/maps/SUPERDM (BIG).wad" ]] && mv "$out/maps/SUPERDM (BIG).wad" "$out/maps/SUPERDM_BIG.wad"
          [[ -f "$out/maps/SUPERDM150 от DUKA.wad" ]] && mv "$out/maps/SUPERDM150 от DUKA.wad" "$out/maps/SUPERDM150.wad"
          [[ -f "$out/maps/MEGADM 2.wad" ]] && mv "$out/maps/MEGADM 2.wad" "$out/maps/MEGADM_2.wad"
          [[ -f "$out/maps/Rock (no mus).wad" ]] && mv "$out/maps/Rock (no mus).wad" "$out/maps/Rock_no_mus.wad"
        '';
      };
      mkD2dfServerJob = name: cfg: let
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
        service = serviceName name;
        timer = timerName name;
        socket = socketName name;
        startScript = startScriptName name;
        isOnLowerPort = cfg.port < 1024;
        doom2df-data = cfg.assets;
      in {
        description = "Doom2D Forever server instance ‘${name}’";
        wantedBy = ["multi-user.target"];
        # FIXME
        # What if master server and regular server are on one machine?
        # Maybe this will work.
        after = ["network.target" "d2df_master_server.service"];
        path = [pkgs.coreutils];

        serviceConfig.ExecStart = let
          printSettings = cfg: settings: (
            (toString
              cfg.prependConfig)
            + "\n"
            + ''
              sv_name "${cfg.name}"
              sv_maxplrs ${builtins.toString cfg.maxPlayers}
              sv_rcon ${
                if cfg.rcon.enable
                then "1"
                else "0"
              }
            ''
            + (
              builtins.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  key: option: let
                    escape = s: lib.replaceStrings ["\""] ["'"] s;
                    quote = s: "\"${s}\"";

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
                        toValue (builtins.concatStringsSep
                          ","
                          (builtins.map (x: builtins.toString x) option))
                      else toValue option
                    );
                  in "${key} ${value}"
                )
                settings
              )
            )
            + "\n"
            + toString cfg.appendConfig
          );
          configFile = pkgs.writeText "${abbr}-server.cfg" (printSettings cfg cfg.settings);
          convertedCfg = convertToWin1251 configFile;
          execFile = pkgs.writeText "${abbr}-server-exec.txt" (
            (lib.optionalString cfg.bots.enable ''
              ${lib.optionalString cfg.bots.allowKick ""}
              ${lib.optionalString cfg.bots.fillEmptyPlayerSlots ""}
              ${lib.concatStringsSep "\n" (lib.replicate cfg.bots.count (
                if cfg.gameMode == "pubg"
                then "bot_addblue"
                else "bot_add"
              ))}
              ${
                if cfg.gameMode == "pubg"
                then "alias addbot bot_addblue"
                else "alias addbot bot_add"
              }
            '')
            + "\n"
            + (builtins.toString cfg.execStart)
          );
          finalMapsJson =
            cfg.mapsJson;
          launchArgs = [
            "-gm ${
              if cfg.gameMode == "pubg"
              then "tdm"
              else if cfg.gameMode == "defrag"
              then "coop"
              # FIXME
              # Should change according to CTF on CTF maps, or always force TDM with autobalancing
              else if cfg.gameMode == "duel"
              then "dm"
              else cfg.gameMode
            }"
            "-pl 0"
            ''-map PrikolSoft.wad:\\MAP01''
            "-port ${builtins.toString cfg.port}"

            (
              if cfg.settings ? g_timelimit
              then "-limt ${builtins.toString cfg.settings.g_timelimit}"
              else ""
            )
            (
              if cfg.settings ? g_scorelimit
              then "-lims ${builtins.toString cfg.settings.g_scorelimit}"
              else ""
            )

            # Keep logs indefinitely by default
            "--keep-logs -1"

            ''--ro-dir "${doom2df-data}" ''
            #''--ro-dir "${inputs.private-flake}/files/doom2d-forever" ''
            ''--ro-dir "${doom2df-dm-maps}" ''
            ''--rw-dir "${baseStatePath}" ''
            ''--config "${cfgBaseName}" ''
            ''--log-file "${
                if cfg.logs.enable
                then "${baseLogsPath}/$(date +\"%F-%T.log\")"
                else "/dev/null"
              }" ''
            ''-exec "${execPath}" ''
          ];
          baseCfgPath = "${baseDir}/${name}";
          baseStatePath = "${baseDir}/${name}";
          baseLogsPath = "${baseDir}/${name}";

          cfgBaseName = "config.cfg";
          cfgPath = "${baseCfgPath}/${cfgBaseName}";
          execBaseName = "exec.txt";
          execPath = "${baseCfgPath}/${execBaseName}";
          script = pkgs.writeShellScriptBin startScript ''
            sleep ${builtins.toString (cfg.order * 6)}s
            TEMP_DIR="$(mktemp -d)/${abbr}-${name}"
            mkdir -p "$TEMP_DIR" "${baseCfgPath}" "${baseStatePath}" "${lib.optionalString cfg.logs.enable baseLogsPath}"
            tempCfgPath="$TEMP_DIR/${cfgBaseName}"
            tempExecPath="$TEMP_DIR/${execBaseName}"

            cat "${convertedCfg}/str" > "$tempCfgPath"
            cat "$tempCfgPath" > "$tempExecPath"
            ${pkgs.nodePackages_latest.nodejs}/bin/node --jitless "${createMapsListSrc finalMapsJson (lib.optionalAttrs (cfg.gameMode == "coop") {generateMode = "perWad";})}" | tee -a "$tempExecPath"
            cat "${execFile}" >> "$tempExecPath"
            ${lib.optionalString cfg.rcon.enable ''
              [ -f "${cfg.rcon.file}" ] && echo -e "sv_rcon_password \"$(cat ${cfg.rcon.file})\"" >> "$tempExecPath" || echo "sv_rcon 0" >> "$tempExecPath"
            ''}
            rm -f "${cfgPath}" "${execPath}"
            ln -s "$tempCfgPath" "${cfgPath}"
            ln -s "$tempExecPath" "${execPath}"
            ${lib.getExe cfg.package} ${builtins.concatStringsSep " " launchArgs}'';
        in "${script}/bin/${startScript}";
        serviceConfig.Restart = "always";
        serviceConfig.Type = "simple";
        serviceConfig.Sockets = [socket];
        serviceConfig.StandardInput = "socket";
        serviceConfig.StandardOutput = "journal";
        serviceConfig.StandardError = "journal";
        serviceConfig.SecureBits = lib.optionalString isOnLowerPort "keep-caps";
        serviceConfig.AmbientCapabilities = lib.optionals isOnLowerPort ["CAP_NET_BIND_SERVICE" "CAP_NET_ADMIN"];
        serviceConfig.CapabilityBoundingSet = lib.optionals isOnLowerPort ["CAP_NET_BIND_SERVICE" "CAP_NET_ADMIN"];
        serviceConfig.SocketBindDeny = "any";
        serviceConfig.SocketBindAllow = ["udp:${builtins.toString cfg.port}"] ++ lib.optionals cfg.ping ["udp:57133"];
        serviceConfig.LogFilterPatterns = let
          playerLeft = "^CON:.*left the game\.";
          connection = "^CON: NET: Somebody is trying to connect from";
          failMaster = "^CON: failed to connect to master at";
          playerJoin = "^CON: NET: Client.*connected. Assigned player";
          chat = "^CON: \\[Chat\\]";
          chatTeam = "^CON: \\[Team Chat\\]";
          whisper = "^CON: \\[Tell.+\\]";

          joinedTheGame = "~.*joined the game.$";
        in
          lib.mkIf cfg.logs.filterMessages [
            playerLeft
            connection
            # failMaster
            playerJoin
            chat
            chatTeam
            whisper

            joinedTheGame
          ];
        serviceConfig.User = user;

        serviceConfig = {
          CPUAccounting = true;
          MemoryAccounting = true;
          MemoryHigh = 48 * 1024 * 1024;
          MemoryMax = 72 * 1024 * 1024;
          TasksAccounting = true;
          IOAccounting = true;
        };

        serviceConfig = {
          NoNewPrivileges = true;
          PrivateDevices = true;
          DevicePolicy = true;
          ProtectSystem = true;
          ProtectHome = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictAddressFamilies = "AF_INET AF_INET6 AF_NETLINK";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
          # breaks CAP_NET_BIND_SERVICE if enabled
          PrivateUsers = !isOnLowerPort;
          ProtectKernelLogs = true;
          PrivateMounts = true;
          ProtectHostname = true;
          #PrivateTmp = true;
          #TemporaryFileSystem = "/:ro";
          #BindPaths = baseDir;
          #BindReadOnlyPaths = doom2df-data;
        };
      };
    in let
      l = lib.attrsToList cfg.servers;
    in
      lib.mkIf cfg.enable {
        networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall (
          [
            # Doom2D Forever ping port
            57133
          ]
          ++ (lib.map (x: x.value.port) l)
        );

        users.users."${user}" = {
          description = "Doom2D Forever service user";
          isSystemUser = true;
          group = user;
        };
        users.groups."${user}" = {};

        systemd = lib.mkMerge (
          [
            {
              tmpfiles.rules = [
                # Recursively change owner to Doom2D Forever service user
                "d '${baseDir}' 0700 ${user} - - -"
                "Z '${baseDir}' 0700 ${user} - - -"
              ];
            }
          ]
          ++ (lib.map (x: let
            serviceName = "${abbr}-${x.name}";
            timerName = "restart_nightly_${serviceName}";
          in
            lib.optionalAttrs x.value.enable {
              services."${serviceName}" = mkD2dfServerJob x.name x.value;
              services."${timerName}" = {
                description = "Restarts ${serviceName} nightly";
                path = [pkgs.systemd];
                serviceConfig.ExecStart = "systemctl restart ${serviceName}.service";
              };
              timers."${timerName}" = {
                description = "Restarts ${serviceName} nightly";
                timerConfig = {
                  OnCalendar = "05:00";
                  AccuracySec = "10min";
                };
                wantedBy = ["timers.target"];
              };
              sockets."${serviceName}" = {
                socketConfig = {
                  ListenFIFO = "%t/${serviceName}.stdin";
                  Service = "${serviceName}.service";
                };
              };
            })
          l)
        );
      });
}
