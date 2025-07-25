{
  config,
  lib,
  pkgs,
  ...
}:
let
  nvidiaEnabled = lib.elem "nvidia" config.services.xserver.videoDrivers;
  nvidia_x11 = if nvidiaEnabled || cfg.datacenter.enable then cfg.package else null;

  cfg = config.hardware.nvidia;

  useOpenModules = cfg.open == true;

  pCfg = cfg.prime;
  syncCfg = pCfg.sync;
  offloadCfg = pCfg.offload;
  reverseSyncCfg = pCfg.reverseSync;
  primeEnabled = syncCfg.enable || reverseSyncCfg.enable || offloadCfg.enable;
  busIDType = lib.types.strMatching "([[:print:]]+:[0-9]{1,3}(@[0-9]{1,10})?:[0-9]{1,2}:[0-9])?";
  ibtSupport = useOpenModules || (nvidia_x11.ibtSupport or false);
  settingsFormat = pkgs.formats.keyValue { };
in
{
  options = {
    hardware.nvidia = {
      enabled = lib.mkOption {
        readOnly = true;
        type = lib.types.bool;
        default = nvidia_x11 != null;
        defaultText = lib.literalMD "`true` if NVIDIA support is enabled";
        description = "True if NVIDIA support is enabled";
      };
      datacenter.enable = lib.mkEnableOption ''
        Data Center drivers for NVIDIA cards on a NVLink topology
      '';
      datacenter.settings = lib.mkOption {
        type = settingsFormat.type;
        default = {
          LOG_LEVEL = 4;
          LOG_FILE_NAME = "/var/log/fabricmanager.log";
          LOG_APPEND_TO_LOG = 1;
          LOG_FILE_MAX_SIZE = 1024;
          LOG_USE_SYSLOG = 0;
          DAEMONIZE = 1;
          BIND_INTERFACE_IP = "127.0.0.1";
          STARTING_TCP_PORT = 16000;
          FABRIC_MODE = 0;
          FABRIC_MODE_RESTART = 0;
          STATE_FILE_NAME = "/var/tmp/fabricmanager.state";
          FM_CMD_BIND_INTERFACE = "127.0.0.1";
          FM_CMD_PORT_NUMBER = 6666;
          FM_STAY_RESIDENT_ON_FAILURES = 0;
          ACCESS_LINK_FAILURE_MODE = 0;
          TRUNK_LINK_FAILURE_MODE = 0;
          NVSWITCH_FAILURE_MODE = 0;
          ABORT_CUDA_JOBS_ON_FM_EXIT = 1;
        };
        defaultText = lib.literalExpression ''
          {
            LOG_LEVEL=4;
            LOG_FILE_NAME="/var/log/fabricmanager.log";
            LOG_APPEND_TO_LOG=1;
            LOG_FILE_MAX_SIZE=1024;
            LOG_USE_SYSLOG=0;
            DAEMONIZE=1;
            BIND_INTERFACE_IP="127.0.0.1";
            STARTING_TCP_PORT=16000;
            FABRIC_MODE=0;
            FABRIC_MODE_RESTART=0;
            STATE_FILE_NAME="/var/tmp/fabricmanager.state";
            FM_CMD_BIND_INTERFACE="127.0.0.1";
            FM_CMD_PORT_NUMBER=6666;
            FM_STAY_RESIDENT_ON_FAILURES=0;
            ACCESS_LINK_FAILURE_MODE=0;
            TRUNK_LINK_FAILURE_MODE=0;
            NVSWITCH_FAILURE_MODE=0;
            ABORT_CUDA_JOBS_ON_FM_EXIT=1;
          }
        '';
        description = ''
          Additional configuration options for fabricmanager.
        '';
      };

      powerManagement.enable = lib.mkEnableOption ''
        experimental power management through systemd. For more information, see
        the NVIDIA docs, on Chapter 21. Configuring Power Management Support
      '';

      powerManagement.finegrained = lib.mkEnableOption ''
        experimental power management of PRIME offload. For more information, see
        the NVIDIA docs, on Chapter 22. PCI-Express Runtime D3 (RTD3) Power Management
      '';

      dynamicBoost.enable = lib.mkEnableOption ''
        dynamic Boost balances power between the CPU and the GPU for improved
        performance on supported laptops using the nvidia-powerd daemon. For more
        information, see the NVIDIA docs, on Chapter 23. Dynamic Boost on Linux
      '';

      modesetting.enable =
        lib.mkEnableOption ''
          kernel modesetting when using the NVIDIA proprietary driver.

          Enabling this fixes screen tearing when using Optimus via PRIME (see
          {option}`hardware.nvidia.prime.sync.enable`. This is not enabled
          by default because it is not officially supported by NVIDIA and would not
          work with SLI.

          Enabling this and using version 545 or newer of the proprietary NVIDIA
          driver causes it to provide its own framebuffer device, which can cause
          Wayland compositors to work when they otherwise wouldn't.
        ''
        // {
          default = lib.versionAtLeast cfg.package.version "535";
          defaultText = lib.literalExpression "lib.versionAtLeast cfg.package.version \"535\"";
        };

      prime.nvidiaBusId = lib.mkOption {
        type = busIDType;
        default = "";
        example = "PCI:1@0:0:0";
        description = ''
          Bus ID of the NVIDIA GPU. You can find it using lspci; for example if lspci
          shows the NVIDIA GPU at "0001:02:03.4", set this option to "PCI:2@1:3:4".

          lspci might omit the PCI domain (0001 in above example) if it is zero.
          In which case, use "@0" instead.

          Please be aware that this option takes decimal address while lspci reports
          hexadecimal address. So for device at domain "10000", use "@65536".
        '';
      };

      prime.intelBusId = lib.mkOption {
        type = busIDType;
        default = "";
        example = "PCI:0@0:2:0";
        description = ''
          Bus ID of the Intel GPU. You can find it using lspci; for example if lspci
          shows the Intel GPU at "0001:02:03.4", set this option to "PCI:2@1:3:4".

          lspci might omit the PCI domain (0001 in above example) if it is zero.
          In which case, use "@0" instead.

          Please be aware that this option takes decimal address while lspci reports
          hexadecimal address. So for device at domain "10000", use "@65536".
        '';
      };

      prime.amdgpuBusId = lib.mkOption {
        type = busIDType;
        default = "";
        example = "PCI:4@0:0:0";
        description = ''
          Bus ID of the AMD APU. You can find it using lspci; for example if lspci
          shows the AMD APU at "0001:02:03.4", set this option to "PCI:2@1:3:4".

          lspci might omit the PCI domain (0001 in above example) if it is zero.
          In which case, use "@0" instead.

          Please be aware that this option takes decimal address while lspci reports
          hexadecimal address. So for device at domain "10000", use "@65536".
        '';
      };

      prime.sync.enable = lib.mkEnableOption ''
        NVIDIA Optimus support using the NVIDIA proprietary driver via PRIME.
        If enabled, the NVIDIA GPU will be always on and used for all rendering,
        while enabling output to displays attached only to the integrated Intel/AMD
        GPU without a multiplexer.

        Note that this option only has any effect if the "nvidia" driver is specified
        in {option}`services.xserver.videoDrivers`, and it should preferably
        be the only driver there.

        If this is enabled, then the bus IDs of the NVIDIA and Intel/AMD GPUs have to
        be specified ({option}`hardware.nvidia.prime.nvidiaBusId` and
        {option}`hardware.nvidia.prime.intelBusId` or
        {option}`hardware.nvidia.prime.amdgpuBusId`).

        If you enable this, you may want to also enable kernel modesetting for the
        NVIDIA driver ({option}`hardware.nvidia.modesetting.enable`) in order
        to prevent tearing.

        Note that this configuration will only be successful when a display manager
        for which the {option}`services.xserver.displayManager.setupCommands`
        option is supported is used
      '';

      prime.allowExternalGpu = lib.mkEnableOption ''
        configuring X to allow external NVIDIA GPUs when using Prime [Reverse] sync optimus
      '';

      prime.offload.enable = lib.mkEnableOption ''
        render offload support using the NVIDIA proprietary driver via PRIME.

        If this is enabled, then the bus IDs of the NVIDIA and Intel/AMD GPUs have to
        be specified ({option}`hardware.nvidia.prime.nvidiaBusId` and
        {option}`hardware.nvidia.prime.intelBusId` or
        {option}`hardware.nvidia.prime.amdgpuBusId`)
      '';

      prime.offload.enableOffloadCmd = lib.mkEnableOption ''
        adding a `nvidia-offload` convenience script to {option}`environment.systemPackages`
        for offloading programs to an nvidia device. To work, you must also enable
        {option}`hardware.nvidia.prime.offload.enable` or {option}`hardware.nvidia.prime.reverseSync.enable`.

        Example usage: `nvidia-offload sauerbraten_client`

        This script can be renamed with {option}`hardware.nvidia.prime.offload.enableOffloadCmd`.
      '';
      prime.offload.offloadCmdMainProgram = lib.mkOption {
        type = lib.types.str;
        description = ''
          Specifies the CLI name of the {option}`hardware.nvidia.prime.offload.enableOffloadCmd`
          convenience script for offloading programs to an nvidia device.
        '';
        default = "nvidia-offload";
        example = "prime-run";
      };

      prime.reverseSync.enable = lib.mkEnableOption ''
        NVIDIA Optimus support using the NVIDIA proprietary driver via reverse
        PRIME. If enabled, the Intel/AMD GPU will be used for all rendering, while
        enabling output to displays attached only to the NVIDIA GPU without a
        multiplexer.

        Warning: This feature is relatively new, depending on your system this might
        work poorly. AMD support, especially so.
        See: https://forums.developer.nvidia.com/t/the-all-new-outputsink-feature-aka-reverse-prime/129828

        Note that this option only has any effect if the "nvidia" driver is specified
        in {option}`services.xserver.videoDrivers`, and it should preferably
        be the only driver there.

        If this is enabled, then the bus IDs of the NVIDIA and Intel/AMD GPUs have to
        be specified ({option}`hardware.nvidia.prime.nvidiaBusId` and
        {option}`hardware.nvidia.prime.intelBusId` or
        {option}`hardware.nvidia.prime.amdgpuBusId`).

        If you enable this, you may want to also enable kernel modesetting for the
        NVIDIA driver ({option}`hardware.nvidia.modesetting.enable`) in order
        to prevent tearing.

        Note that this configuration will only be successful when a display manager
        for which the {option}`services.xserver.displayManager.setupCommands`
        option is supported is used
      '';

      prime.reverseSync.setupCommands.enable =
        (lib.mkEnableOption ''
          configure the display manager to be able to use the outputs
          attached to the NVIDIA GPU.
          Disable in order to configure the NVIDIA GPU outputs manually using xrandr.
          Note that this configuration will only be successful when a display manager
          for which the {option}`services.xserver.displayManager.setupCommands`
          option is supported is used
        '')
        // {
          default = true;
        };

      nvidiaSettings =
        (lib.mkEnableOption ''
          nvidia-settings, NVIDIA's GUI configuration tool
        '')
        // {
          default = true;
        };

      nvidiaPersistenced = lib.mkEnableOption ''
        nvidia-persistenced a update for NVIDIA GPU headless mode, i.e.
        It ensures all GPUs stay awake even during headless mode
      '';

      forceFullCompositionPipeline = lib.mkEnableOption ''
        forcefully the full composition pipeline.
        This sometimes fixes screen tearing issues.
        This has been reported to reduce the performance of some OpenGL applications and may produce issues in WebGL.
        It also drastically increases the time the driver needs to clock down after load
      '';

      package = lib.mkOption {
        default =
          config.boot.kernelPackages.nvidiaPackages."${if cfg.datacenter.enable then "dc" else "stable"}";
        defaultText = lib.literalExpression ''
          config.boot.kernelPackages.nvidiaPackages."\$\{if cfg.datacenter.enable then "dc" else "stable"}"
        '';
        example = "config.boot.kernelPackages.nvidiaPackages.legacy_470";
        description = ''
          The NVIDIA driver package to use.
        '';
      };

      open = lib.mkOption {
        example = true;
        description = "Whether to enable the open source NVIDIA kernel module.";
        type = lib.types.nullOr lib.types.bool;
        default = if lib.versionOlder nvidia_x11.version "560" then false else null;
        defaultText = lib.literalExpression ''
          if lib.versionOlder config.hardware.nvidia.package.version "560" then false else null
        '';
      };

      gsp.enable =
        lib.mkEnableOption ''
          the GPU System Processor (GSP) on the video card
        ''
        // {
          default = useOpenModules || lib.versionAtLeast nvidia_x11.version "555";
          defaultText = lib.literalExpression ''
            config.hardware.nvidia.open == true || lib.versionAtLeast config.hardware.nvidia.package.version "555"
          '';
        };

      videoAcceleration =
        (lib.mkEnableOption ''
          Whether video acceleration (VA-API) should be enabled.
        '')
        // {
          default = true;
        };
    };
  };

  config =
    let
      igpuDriver = if pCfg.intelBusId != "" then "modesetting" else "amdgpu";
      igpuBusId = if pCfg.intelBusId != "" then pCfg.intelBusId else pCfg.amdgpuBusId;
    in
    lib.mkIf cfg.enabled (
      lib.mkMerge [
        # Common
        ({
          assertions = [
            {
              assertion = !(nvidiaEnabled && cfg.datacenter.enable);
              message = "You cannot configure both X11 and Data Center drivers at the same time.";
            }
            {
              assertion = cfg.open != null || cfg.datacenter.enable;
              message = ''
                You must configure `hardware.nvidia.open` on NVIDIA driver versions >= 560.
                It is suggested to use the open source kernel modules on Turing or later GPUs (RTX series, GTX 16xx), and the closed source modules otherwise.
              '';
            }
          ];
          boot = {
            blacklistedKernelModules = [
              "nouveau"
              "nvidiafb"
            ];

            # Don't add `nvidia-uvm` to `kernelModules`, because we want
            # `nvidia-uvm` be loaded only after the GPU device is available, i.e. after `udev` rules
            # for `nvidia` kernel module are applied.
            # This matters on Azure GPU instances: https://github.com/NixOS/nixpkgs/pull/267335
            #
            # Instead, we use `softdep` to lazily load `nvidia-uvm` kernel module
            # after `nvidia` kernel module is loaded and `udev` rules are applied.
            extraModprobeConfig = ''
              softdep nvidia post: nvidia-uvm
            '';

            # Exception is the open-source kernel module failing to load nvidia-uvm using softdep
            # for unknown reasons.
            # It affects CUDA: https://github.com/NixOS/nixpkgs/issues/334180
            # Previously nvidia-uvm was explicitly loaded only when xserver was enabled:
            # https://github.com/NixOS/nixpkgs/pull/334340/commits/4548c392862115359e50860bcf658cfa8715bde9
            # We are now loading the module eagerly for all users of the open driver (including headless).
            kernelModules = lib.optionals useOpenModules [ "nvidia_uvm" ];
          };
          systemd.tmpfiles.rules = lib.mkIf config.virtualisation.docker.enableNvidia [
            "L+ /run/nvidia-docker/bin - - - - ${nvidia_x11.bin}/origBin"
          ];
          services.udev.extraRules = ''
            # Create /dev/nvidia-uvm when the nvidia-uvm module is loaded.
            KERNEL=="nvidia", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidiactl c 195 255'"
            KERNEL=="nvidia", RUN+="${pkgs.runtimeShell} -c 'for i in $$(cat /proc/driver/nvidia/gpus/*/information | grep Minor | cut -d \  -f 4); do mknod -m 666 /dev/nvidia$${i} c 195 $${i}; done'"
            KERNEL=="nvidia_modeset", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidia-modeset c 195 254'"
            KERNEL=="nvidia_uvm", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidia-uvm c $$(grep nvidia-uvm /proc/devices | cut -d \  -f 1) 0'"
            KERNEL=="nvidia_uvm", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidia-uvm-tools c $$(grep nvidia-uvm /proc/devices | cut -d \  -f 1) 1'"
          '';
          hardware.graphics = {
            extraPackages = [ nvidia_x11.out ];
            extraPackages32 = [ nvidia_x11.lib32 ];
          };
          environment.systemPackages = [ nvidia_x11.bin ];
        })

        # X11
        (lib.mkIf nvidiaEnabled {
          assertions = [
            {
              assertion = primeEnabled -> pCfg.intelBusId == "" || pCfg.amdgpuBusId == "";
              message = "You cannot configure both an Intel iGPU and an AMD APU. Pick the one corresponding to your processor.";
            }

            {
              assertion = offloadCfg.enableOffloadCmd -> offloadCfg.enable || reverseSyncCfg.enable;
              message = "Offload command requires offloading or reverse prime sync to be enabled.";
            }

            {
              assertion =
                primeEnabled -> pCfg.nvidiaBusId != "" && (pCfg.intelBusId != "" || pCfg.amdgpuBusId != "");
              message = "When NVIDIA PRIME is enabled, the GPU bus IDs must be configured.";
            }

            {
              assertion = offloadCfg.enable -> lib.versionAtLeast nvidia_x11.version "435.21";
              message = "NVIDIA PRIME render offload is currently only supported on versions >= 435.21.";
            }

            {
              assertion =
                (reverseSyncCfg.enable && pCfg.amdgpuBusId != "") -> lib.versionAtLeast nvidia_x11.version "470.0";
              message = "NVIDIA PRIME render offload for AMD APUs is currently only supported on versions >= 470 beta.";
            }

            {
              assertion = !(syncCfg.enable && offloadCfg.enable);
              message = "PRIME Sync and Offload cannot be both enabled";
            }

            {
              assertion = !(syncCfg.enable && reverseSyncCfg.enable);
              message = "PRIME Sync and PRIME Reverse Sync cannot be both enabled";
            }

            {
              assertion = !(syncCfg.enable && cfg.powerManagement.finegrained);
              message = "Sync precludes powering down the NVIDIA GPU.";
            }

            {
              assertion = cfg.powerManagement.finegrained -> offloadCfg.enable;
              message = "Fine-grained power management requires offload to be enabled.";
            }

            {
              assertion = cfg.powerManagement.enable -> lib.versionAtLeast nvidia_x11.version "430.09";
              message = "Required files for driver based power management only exist on versions >= 430.09.";
            }

            {
              assertion = cfg.gsp.enable -> (cfg.package ? firmware);
              message = "This version of NVIDIA driver does not provide a GSP firmware.";
            }

            {
              assertion = useOpenModules -> (cfg.package ? open);
              message = "This version of NVIDIA driver does not provide a corresponding opensource kernel driver.";
            }

            {
              assertion = useOpenModules -> cfg.gsp.enable;
              message = "The GSP cannot be disabled when using the opensource kernel driver.";
            }

            {
              assertion = cfg.dynamicBoost.enable -> lib.versionAtLeast nvidia_x11.version "510.39.01";
              message = "NVIDIA's Dynamic Boost feature only exists on versions >= 510.39.01";
            }
          ];

          # If Optimus/PRIME is enabled, we:
          # - Specify the configured NVIDIA GPU bus ID in the Device section for the
          #   "nvidia" driver.
          # - Add the AllowEmptyInitialConfiguration option to the Screen section for the
          #   "nvidia" driver, in order to allow the X server to start without any outputs.
          # - Add a separate Device section for the Intel GPU, using the "modesetting"
          #   driver and with the configured BusID.
          # - OR add a separate Device section for the AMD APU, using the "amdgpu"
          #   driver and with the configures BusID.
          # - Reference that Device section from the ServerLayout section as an inactive
          #   device.
          # - Configure the display manager to run specific `xrandr` commands which will
          #   configure/enable displays connected to the Intel iGPU / AMD APU.

          # reverse sync implies offloading
          hardware.nvidia.prime.offload.enable = lib.mkDefault reverseSyncCfg.enable;

          services.xserver.drivers =
            lib.optional primeEnabled {
              name = igpuDriver;
              display = offloadCfg.enable;
              modules = lib.optional (igpuDriver == "amdgpu") pkgs.xorg.xf86videoamdgpu;
              deviceSection = ''
                BusID "${igpuBusId}"
              ''
              + lib.optionalString (syncCfg.enable && igpuDriver != "amdgpu") ''
                Option "AccelMethod" "none"
              '';
            }
            ++ lib.singleton {
              name = "nvidia";
              modules = [ nvidia_x11.bin ];
              display = !offloadCfg.enable;
              deviceSection = ''
                Option "SidebandSocketPath" "/run/nvidia-xdriver/"
              ''
              + lib.optionalString primeEnabled ''
                BusID "${pCfg.nvidiaBusId}"
              ''
              + lib.optionalString pCfg.allowExternalGpu ''
                Option "AllowExternalGpus"
              '';
              screenSection = ''
                Option "RandRRotation" "on"
              ''
              + lib.optionalString syncCfg.enable ''
                Option "AllowEmptyInitialConfiguration"
              ''
              + lib.optionalString cfg.forceFullCompositionPipeline ''
                Option         "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
                Option         "AllowIndirectGLXProtocol" "off"
                Option         "TripleBuffer" "on"
              '';
            };

          services.xserver.serverLayoutSection =
            lib.optionalString syncCfg.enable ''
              Inactive "Device-${igpuDriver}[0]"
            ''
            + lib.optionalString reverseSyncCfg.enable ''
              Inactive "Device-nvidia[0]"
            ''
            + lib.optionalString offloadCfg.enable ''
              Option "AllowNVIDIAGPUScreens"
            '';

          services.xserver.displayManager.setupCommands =
            let
              gpuProviderName =
                if igpuDriver == "amdgpu" then
                  # find the name of the provider if amdgpu
                  "`${lib.getExe pkgs.xorg.xrandr} --listproviders | ${lib.getExe pkgs.gnugrep} -i AMD | ${lib.getExe pkgs.gnused} -n 's/^.*name://p'`"
                else
                  igpuDriver;
              providerCmdParams =
                if syncCfg.enable then "\"${gpuProviderName}\" NVIDIA-0" else "NVIDIA-G0 \"${gpuProviderName}\"";
            in
            lib.optionalString
              (syncCfg.enable || (reverseSyncCfg.enable && reverseSyncCfg.setupCommands.enable))
              ''
                # Added by nvidia configuration module for Optimus/PRIME.
                ${lib.getExe pkgs.xorg.xrandr} --setprovideroutputsource ${providerCmdParams}
                ${lib.getExe pkgs.xorg.xrandr} --auto
              '';

          environment.etc = {
            "nvidia/nvidia-application-profiles-rc" = lib.mkIf nvidia_x11.useProfiles {
              source = "${nvidia_x11.bin}/share/nvidia/nvidia-application-profiles-rc";
            };

            # 'nvidia_x11' installs it's files to /run/opengl-driver/...
            "egl/egl_external_platform.d".source = "/run/opengl-driver/share/egl/egl_external_platform.d/";
          };

          hardware.graphics.extraPackages = lib.optional cfg.videoAcceleration pkgs.nvidia-vaapi-driver;

          environment.systemPackages =
            lib.optional cfg.nvidiaSettings nvidia_x11.settings
            ++ lib.optional cfg.nvidiaPersistenced nvidia_x11.persistenced
            ++ lib.optional offloadCfg.enableOffloadCmd (
              pkgs.writeShellScriptBin cfg.prime.offload.offloadCmdMainProgram ''
                export __NV_PRIME_RENDER_OFFLOAD=1
                export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
                export __GLX_VENDOR_LIBRARY_NAME=nvidia
                export __VK_LAYER_NV_optimus=NVIDIA_only
                exec "$@"
              ''
            );

          systemd.packages = lib.optional cfg.powerManagement.enable nvidia_x11.out;

          systemd.services =
            let
              nvidiaService = state: {
                description = "NVIDIA system ${state} actions";
                path = [ pkgs.kbd ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${nvidia_x11.out}/bin/nvidia-sleep.sh '${state}'";
                };
                before = [ "systemd-${state}.service" ];
                requiredBy = [ "systemd-${state}.service" ];
              };
            in
            lib.mkMerge [
              (lib.mkIf cfg.powerManagement.enable {
                nvidia-suspend = nvidiaService "suspend";
                nvidia-hibernate = nvidiaService "hibernate";
                nvidia-resume = (nvidiaService "resume") // {
                  before = [ ];
                  after = [
                    "systemd-suspend.service"
                    "systemd-hibernate.service"
                  ];
                  requiredBy = [
                    "systemd-suspend.service"
                    "systemd-hibernate.service"
                  ];
                };
              })
              (lib.mkIf cfg.nvidiaPersistenced {
                "nvidia-persistenced" = {
                  description = "NVIDIA Persistence Daemon";
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "forking";
                    Restart = "always";
                    PIDFile = "/var/run/nvidia-persistenced/nvidia-persistenced.pid";
                    ExecStart = "${lib.getExe nvidia_x11.persistenced} --verbose";
                    ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-persistenced";
                  };
                };
              })
              (lib.mkIf cfg.dynamicBoost.enable {
                "nvidia-powerd" = {
                  description = "nvidia-powerd service";
                  path = [
                    pkgs.util-linux # nvidia-powerd wants lscpu
                  ];
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "dbus";
                    BusName = "nvidia.powerd.server";
                    ExecStart = "${nvidia_x11.bin}/bin/nvidia-powerd";
                  };
                };
              })
            ];

          services.acpid.enable = true;

          services.dbus.packages = lib.optional cfg.dynamicBoost.enable nvidia_x11.bin;

          hardware.firmware = lib.optional cfg.gsp.enable nvidia_x11.firmware;

          systemd.tmpfiles.rules = [
            # Remove the following log message:
            #    (WW) NVIDIA: Failed to bind sideband socket to
            #    (WW) NVIDIA:     '/var/run/nvidia-xdriver-b4f69129' Permission denied
            #
            # https://bbs.archlinux.org/viewtopic.php?pid=1909115#p1909115
            "d /run/nvidia-xdriver 0770 root users"
          ]
          ++
            lib.optional (nvidia_x11.persistenced != null && config.virtualisation.docker.enableNvidia)
              "L+ /run/nvidia-docker/extras/bin/nvidia-persistenced - - - - ${nvidia_x11.persistenced}/origBin/nvidia-persistenced";

          boot = {
            extraModulePackages = if useOpenModules then [ nvidia_x11.open ] else [ nvidia_x11.bin ];
            # nvidia-uvm is required by CUDA applications.
            kernelModules = lib.optionals config.services.xserver.enable [
              "nvidia"
              "nvidia_modeset"
              "nvidia_drm"
            ];

            # If requested enable modesetting via kernel parameters.
            kernelParams =
              lib.optional (offloadCfg.enable || cfg.modesetting.enable) "nvidia-drm.modeset=1"
              ++ lib.optional (
                (offloadCfg.enable || cfg.modesetting.enable) && lib.versionAtLeast nvidia_x11.version "545"
              ) "nvidia-drm.fbdev=1"
              ++ lib.optional cfg.powerManagement.enable "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
              ++ lib.optional useOpenModules "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
              ++ lib.optional (config.boot.kernelPackages.kernel.kernelAtLeast "6.2" && !ibtSupport) "ibt=off";

            # enable finegrained power management
            extraModprobeConfig = lib.optionalString cfg.powerManagement.finegrained ''
              options nvidia "NVreg_DynamicPowerManagement=0x02"
            '';
          };
          services.udev.extraRules = lib.optionalString cfg.powerManagement.finegrained (
            lib.optionalString (lib.versionOlder config.boot.kernelPackages.kernel.version "5.5") ''
              # Remove NVIDIA USB xHCI Host Controller devices, if present
              ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{remove}="1"

              # Remove NVIDIA USB Type-C UCSI devices, if present
              ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{remove}="1"

              # Remove NVIDIA Audio devices, if present
              ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{remove}="1"
            ''
            + ''
              # Enable runtime PM for NVIDIA VGA/3D controller devices on driver bind
              ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
              ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"

              # Disable runtime PM for NVIDIA VGA/3D controller devices on driver unbind
              ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
              ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
            ''
          );
        })
        # Data Center
        (lib.mkIf (cfg.datacenter.enable) {
          boot.extraModulePackages = [ nvidia_x11.bin ];

          systemd = {
            tmpfiles.rules =
              lib.optional (nvidia_x11.persistenced != null && config.virtualisation.docker.enableNvidia)
                "L+ /run/nvidia-docker/extras/bin/nvidia-persistenced - - - - ${nvidia_x11.persistenced}/origBin/nvidia-persistenced";

            services = lib.mkMerge [
              ({
                nvidia-fabricmanager = {
                  enable = true;
                  description = "Start NVIDIA NVLink Management";
                  wantedBy = [ "multi-user.target" ];
                  unitConfig.After = [ "network-online.target" ];
                  unitConfig.Requires = [ "network-online.target" ];
                  serviceConfig = {
                    Type = "forking";
                    TimeoutStartSec = 240;
                    ExecStart =
                      let
                        # Since these rely on the `nvidia_x11.fabricmanager` derivation, they're
                        # unsuitable to be mentioned in the configuration defaults, but they _can_
                        # be overridden in `cfg.datacenter.settings` if needed.
                        fabricManagerConfDefaults = {
                          TOPOLOGY_FILE_PATH = "${nvidia_x11.fabricmanager}/share/nvidia-fabricmanager/nvidia/nvswitch";
                          DATABASE_PATH = "${nvidia_x11.fabricmanager}/share/nvidia-fabricmanager/nvidia/nvswitch";
                        };
                        nv-fab-conf = settingsFormat.generate "fabricmanager.conf" (
                          fabricManagerConfDefaults // cfg.datacenter.settings
                        );
                      in
                      "${lib.getExe nvidia_x11.fabricmanager} -c ${nv-fab-conf}";
                    LimitCORE = "infinity";
                  };
                };
              })
              (lib.mkIf cfg.nvidiaPersistenced {
                "nvidia-persistenced" = {
                  description = "NVIDIA Persistence Daemon";
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "forking";
                    Restart = "always";
                    PIDFile = "/var/run/nvidia-persistenced/nvidia-persistenced.pid";
                    ExecStart = "${lib.getExe nvidia_x11.persistenced} --verbose";
                    ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-persistenced";
                  };
                };
              })
            ];
          };

          environment.systemPackages =
            lib.optional cfg.datacenter.enable nvidia_x11.fabricmanager
            ++ lib.optional cfg.nvidiaPersistenced nvidia_x11.persistenced;
        })
      ]
    );
}
