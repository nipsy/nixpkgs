{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  undmg,
  makeWrapper,
  asar,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  curl,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  libGL,
  libappindicator-gtk3,
  libdrm,
  libnotify,
  libpulseaudio,
  libuuid,
  libxcb,
  libxkbcommon,
  libxshmfence,
  libgbm,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  wayland,
  xdg-utils,
  xorg,
}:

let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "slack does not support system: ${system}";

  pname = "slack";

  x86_64-darwin-version = "4.44.65";
  x86_64-darwin-sha256 = "14y33ds3ncgxwlcb0gvi8pfxm7ppfipzalg63x5vnj05q9wn8lby";

  x86_64-linux-version = "4.44.65";
  x86_64-linux-sha256 = "ca6ce66685e5897db0b19a79275e9c244693ebaf64a6b2f12a79a2b442d5be47";

  aarch64-darwin-version = "4.44.65";
  aarch64-darwin-sha256 = "1gdvvz2dd06din31qparwhnghjcxmvrc2zll09b3lfhr11im7888";

  version =
    {
      x86_64-darwin = x86_64-darwin-version;
      x86_64-linux = x86_64-linux-version;
      aarch64-darwin = aarch64-darwin-version;
    }
    .${system} or throwSystem;

  src =
    let
      base = "https://downloads.slack-edge.com";
    in
    {
      x86_64-darwin = fetchurl {
        url = "${base}/desktop-releases/mac/universal/${version}/Slack-${version}-macOS.dmg";
        sha256 = x86_64-darwin-sha256;
      };
      x86_64-linux = fetchurl {
        url = "${base}/desktop-releases/linux/x64/${version}/slack-desktop-${version}-amd64.deb";
        sha256 = x86_64-linux-sha256;
      };
      aarch64-darwin = fetchurl {
        url = "${base}/desktop-releases/mac/arm64/${version}/Slack-${version}-macOS.dmg";
        sha256 = aarch64-darwin-sha256;
      };
    }
    .${system} or throwSystem;

  meta = with lib; {
    description = "Desktop client for Slack";
    homepage = "https://slack.com";
    changelog = "https://slack.com/release-notes";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.unfree;
    maintainers = with maintainers; [
      mmahut
      teutat3s
    ];
    platforms = [
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "slack";
  };

  linux = stdenv.mkDerivation rec {
    inherit
      pname
      version
      src
      meta
      ;

    passthru.updateScript = ./update.sh;

    rpath =
      lib.makeLibraryPath [
        alsa-lib
        at-spi2-atk
        at-spi2-core
        atk
        cairo
        cups
        curl
        dbus
        expat
        fontconfig
        freetype
        gdk-pixbuf
        glib
        gtk3
        libGL
        libappindicator-gtk3
        libdrm
        libnotify
        libpulseaudio
        libuuid
        libxcb
        libxkbcommon
        libgbm
        nspr
        nss
        pango
        pipewire
        stdenv.cc.cc
        systemd
        wayland
        xorg.libX11
        xorg.libXScrnSaver
        xorg.libXcomposite
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrandr
        xorg.libXrender
        xorg.libXtst
        xorg.libxkbfile
        xorg.libxshmfence
      ]
      + ":${lib.getLib stdenv.cc.cc}/lib64";

    buildInputs = [
      gtk3 # needed for GSETTINGS_SCHEMAS_PATH
    ];

    nativeBuildInputs = [
      dpkg
      makeWrapper
      asar
    ];

    dontUnpack = true;
    dontBuild = true;
    dontPatchELF = true;

    installPhase = ''
      runHook preInstall

      # The deb file contains a setuid binary, so 'dpkg -x' doesn't work here
      dpkg --fsys-tarfile $src | tar --extract
      rm -rf usr/share/lintian

      mkdir -p $out
      mv usr/* $out

      # Otherwise it looks "suspicious"
      chmod -R g-w $out

      for file in $(find $out -type f \( -perm /0111 -o -name \*.so\* \) ); do
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$file" || true
        patchelf --set-rpath ${rpath}:$out/lib/slack $file || true
      done

      # Replace the broken bin/slack symlink with a startup wrapper.
      # Make xdg-open overrideable at runtime.
      rm $out/bin/slack
      makeWrapper $out/lib/slack/slack $out/bin/slack \
        --prefix XDG_DATA_DIRS : $GSETTINGS_SCHEMAS_PATH \
        --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer --enable-wayland-ime=true}}"

      # Fix the desktop link
      substituteInPlace $out/share/applications/slack.desktop \
        --replace /usr/bin/ $out/bin/ \
        --replace /usr/share/pixmaps/slack.png slack \
        --replace bin/slack "bin/slack -s"
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      # Prevent Un-blacklist pipewire integration to enable screen sharing on wayland.
      # https://github.com/flathub/com.slack.Slack/issues/101#issuecomment-1807073763
      sed -i -e 's/,"WebRTCPipeWireCapturer"/,"LebRTCPipeWireCapturer"/' $out/lib/slack/resources/app.asar
    ''
    + ''
      runHook postInstall
    '';
  };

  darwin = stdenv.mkDerivation {
    inherit
      pname
      version
      src
      meta
      ;

    passthru.updateScript = ./update.sh;

    nativeBuildInputs = [ undmg ];

    sourceRoot = "Slack.app";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications/Slack.app
      cp -R . $out/Applications/Slack.app
      runHook postInstall
    '';
  };
in
if stdenv.hostPlatform.isDarwin then darwin else linux
