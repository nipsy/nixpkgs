{
  config,
  pkgs,
  lib,
  ...
}:
let
  dataDir = "/var/lib/mautrix-telegram";
  registrationFile = "${dataDir}/telegram-registration.yaml";
  cfg = config.services.mautrix-telegram;
  settingsFormat = pkgs.formats.json { };
  settingsFileUnsubstituted = settingsFormat.generate "mautrix-telegram-config.json" cfg.settings;
  settingsFile = "${dataDir}/config.json";

in
{
  options = {
    services.mautrix-telegram = {
      enable = lib.mkEnableOption "Mautrix-Telegram, a Matrix-Telegram hybrid puppeting/relaybot bridge";

      package = lib.mkPackageOption pkgs "mautrix-telegram" { };

      settings = lib.mkOption rec {
        apply = lib.recursiveUpdate default;
        inherit (settingsFormat) type;
        default = {
          homeserver = {
            software = "standard";
          };

          appservice = rec {
            database = "sqlite:///${dataDir}/mautrix-telegram.db";
            database_opts = { };
            hostname = "0.0.0.0";
            port = 8080;
            address = "http://localhost:${toString port}";
          };

          bridge = {
            permissions."*" = "relaybot";
            relaybot.whitelist = [ ];
            double_puppet_server_map = { };
            login_shared_secret_map = { };
          };

          logging = {
            version = 1;

            formatters.precise.format = "[%(levelname)s@%(name)s] %(message)s";

            handlers.console = {
              class = "logging.StreamHandler";
              formatter = "precise";
            };

            loggers = {
              mau.level = "INFO";
              telethon.level = "INFO";

              # prevent tokens from leaking in the logs:
              # https://github.com/tulir/mautrix-telegram/issues/351
              aiohttp.level = "WARNING";
            };

            # log to console/systemd instead of file
            root = {
              level = "INFO";
              handlers = [ "console" ];
            };
          };
        };
        example = lib.literalExpression ''
          {
            homeserver = {
              address = "http://localhost:8008";
              domain = "public-domain.tld";
            };

            appservice.public = {
              prefix = "/public";
              external = "https://public-appservice-address/public";
            };

            bridge.permissions = {
              "example.com" = "full";
              "@admin:example.com" = "admin";
            };
            telegram = {
              connection.use_ipv6 = true;
            };
          }
        '';
        description = ''
          {file}`config.yaml` configuration as a Nix attribute set.
          Configuration options should match those described in
          [example-config.yaml](https://github.com/mautrix/telegram/blob/master/mautrix_telegram/example-config.yaml).

          Secret tokens should be specified using {option}`environmentFile`
          instead of this world-readable attribute set.
        '';
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          File containing environment variables to be passed to the mautrix-telegram service,
          in which secret tokens can be specified securely by defining values for e.g.
          `MAUTRIX_TELEGRAM_APPSERVICE_AS_TOKEN`,
          `MAUTRIX_TELEGRAM_APPSERVICE_HS_TOKEN`,
          `MAUTRIX_TELEGRAM_TELEGRAM_API_ID`,
          `MAUTRIX_TELEGRAM_TELEGRAM_API_HASH` and optionally
          `MAUTRIX_TELEGRAM_TELEGRAM_BOT_TOKEN`.

          These environment variables can also be used to set other options by
          replacing hierarchy levels by `.`, converting the name to uppercase
          and prepending `MAUTRIX_TELEGRAM_`.
          For example, the first value above maps to
          {option}`settings.appservice.as_token`.

          The environment variable values can be prefixed with `json::` to have
          them be parsed as JSON. For example, `login_shared_secret_map` can be
          set as follows:
          `MAUTRIX_TELEGRAM_BRIDGE_LOGIN_SHARED_SECRET_MAP=json::{"example.com":"secret"}`.
        '';
      };

      serviceDependencies = lib.mkOption {
        type = with lib.types; listOf str;
        default = lib.optional config.services.matrix-synapse.enable config.services.matrix-synapse.serviceUnit;
        defaultText = lib.literalExpression ''
          lib.optional config.services.matrix-synapse.enable config.services.matrix-synapse.serviceUnit
        '';
        description = ''
          List of Systemd services to require and wait for when starting the application service.
        '';
      };

      registerToSynapse = lib.mkOption {
        type = lib.types.bool;
        default = config.services.matrix-synapse.enable;
        defaultText = lib.literalExpression "config.services.matrix-synapse.enable";
        description = ''
          Whether to add the bridge's app service registration file to
          `services.matrix-synapse.settings.app_service_config_files`.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    users.users.mautrix-telegram = {
      isSystemUser = true;
      group = "mautrix-telegram";
      home = dataDir;
      description = "Mautrix-Telegram bridge user";
    };

    users.groups.mautrix-telegram = { };

    services.matrix-synapse = lib.mkIf cfg.registerToSynapse {
      settings.app_service_config_files = [ registrationFile ];
    };
    systemd.services.matrix-synapse = lib.mkIf cfg.registerToSynapse {
      serviceConfig.SupplementaryGroups = [ "mautrix-telegram" ];
    };

    systemd.services.mautrix-telegram = {
      description = "Mautrix-Telegram, a Matrix-Telegram hybrid puppeting/relaybot bridge.";

      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ] ++ cfg.serviceDependencies;
      after = [ "network-online.target" ] ++ cfg.serviceDependencies;
      path = [
        pkgs.lottieconverter
        pkgs.ffmpeg-headless
      ];

      # mautrix-telegram tries to generate a dotfile in the home directory of
      # the running user if using a postgresql database:
      #
      #  File "python3.10/site-packages/asyncpg/connect_utils.py", line 257, in _dot_postgre>
      #    return (pathlib.Path.home() / '.postgresql' / filename).resolve()
      #  File "python3.10/pathlib.py", line 1000, in home
      #    return cls("~").expanduser()
      #  File "python3.10/pathlib.py", line 1440, in expanduser
      #    raise RuntimeError("Could not determine home directory.")
      # RuntimeError: Could not determine home directory.
      environment.HOME = dataDir;

      preStart = ''
        # substitute the settings file by environment variables
        # in this case read from EnvironmentFile
        test -f '${settingsFile}' && rm -f '${settingsFile}'
        old_umask=$(umask)
        umask 0177
        ${pkgs.envsubst}/bin/envsubst \
          -o '${settingsFile}' \
          -i '${settingsFileUnsubstituted}'
        umask $old_umask

        # generate the appservice's registration file if absent
        if [ ! -f '${registrationFile}' ]; then
          ${cfg.package}/bin/mautrix-telegram \
            --generate-registration \
            --config='${settingsFile}' \
            --registration='${registrationFile}'
        fi

        old_umask=$(umask)
        umask 0177
        # 1. Overwrite registration tokens in config
        #    is set, set it as the login shared secret value for the configured
        #    homeserver domain.
        ${pkgs.yq}/bin/yq -s '.[0].appservice.as_token = .[1].as_token
          | .[0].appservice.hs_token = .[1].hs_token
          | .[0]' \
          '${settingsFile}' '${registrationFile}' > '${settingsFile}.tmp'
        mv '${settingsFile}.tmp' '${settingsFile}'

        umask $old_umask
      ''
      + lib.optionalString (cfg.package ? alembic) ''
        # run automatic database init and migration scripts
        ${cfg.package.alembic}/bin/alembic -x config='${settingsFile}' upgrade head
      '';

      serviceConfig = {
        User = "mautrix-telegram";
        Group = "mautrix-telegram";
        Type = "simple";
        Restart = "always";

        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;

        PrivateTmp = true;
        WorkingDirectory = cfg.package; # necessary for the database migration scripts to be found
        StateDirectory = baseNameOf dataDir;
        UMask = "0027";
        EnvironmentFile = cfg.environmentFile;

        ExecStart = ''
          ${cfg.package}/bin/mautrix-telegram \
            --config='${settingsFile}'
        '';
      };
    };
  };

  meta.maintainers = with lib.maintainers; [
    euxane
    vskilet
  ];
}
