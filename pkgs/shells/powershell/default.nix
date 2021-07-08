{ stdenv
, lib
, autoPatchelfHook
, fetchzip
, libunwind
, libuuid
, icu
, curl
, darwin
, makeWrapper
, less
, openssl_1_1
, pam
, lttng-ust
, keyutils
}:

let
  archString = if stdenv.isAarch64 then "arm64"
    else if stdenv.isx86_64 then "x64"
    else throw "unsupported platform";
  platformString = if stdenv.isDarwin then "osx"
    else if stdenv.isLinux then "linux"
    else throw "unsupported platform";
  platformSha = if stdenv.isDarwin then "0w44ws8b6zfixf7xz93hmplqsx18279n9x8j77y4rbzs13fldvsn"
    else if (stdenv.isLinux && stdenv.isx86_64) then "0xm7l49zhkz2fly3d751kjd5cy3ws9zji9i0061lkd06dvkch7jy"
    else if (stdenv.isLinux && stdenv.isAarch64) then "1axbi4kmb1ydys7c45jhp729w1srid3c8jgivb4bdmdp56rf6h32"
    else throw "unsupported platform";
  platformLdLibraryPath = if stdenv.isDarwin then "DYLD_FALLBACK_LIBRARY_PATH"
    else if stdenv.isLinux then "LD_LIBRARY_PATH"
    else throw "unsupported platform";
  libraries = [ libunwind libuuid icu curl openssl_1_1 ]
    ++ lib.optionals stdenv.isLinux [ pam lttng-ust keyutils ]
    ++ lib.optionals stdenv.isDarwin [ darwin.Libsystem ];
in
stdenv.mkDerivation rec {
  pname = "powershell";
  version = "7.1.3";

  src = fetchzip {
    url = "https://github.com/PowerShell/PowerShell/releases/download/v${version}/powershell-${version}-${platformString}-${archString}.tar.gz";
    sha256 = platformSha;
    stripRoot = false;
  };

  buildInputs = [ less ] ++ libraries;
  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  installPhase =
  let
    ext = stdenv.hostPlatform.extensions.sharedLibrary;
  in ''
    pslibs=$out/share/powershell
    mkdir -p $pslibs

    cp -r * $pslibs

    rm -f $pslibs/libcrypto${ext}.1.0.0
    rm -f $pslibs/libssl${ext}.1.0.0

    # At least the 7.1.3-osx package does not have the executable bit set.
    chmod a+x $pslibs/pwsh

    ls $pslibs
  '' + lib.optionalString (!stdenv.isDarwin && !stdenv.isAarch64) ''
    patchelf --replace-needed libcrypto${ext}.1.0.0 libcrypto${ext}.1.1 $pslibs/libmi.so
    patchelf --replace-needed libssl${ext}.1.0.0 libssl${ext}.1.1 $pslibs/libmi.so
  '' + ''

    mkdir -p $out/bin

    makeWrapper $pslibs/pwsh $out/bin/pwsh \
      --prefix ${platformLdLibraryPath} : "${lib.makeLibraryPath libraries}" \
      --set TERM xterm --set POWERSHELL_TELEMETRY_OPTOUT 1 --set DOTNET_CLI_TELEMETRY_OPTOUT 1
  '';

  dontStrip = true;

  doInstallCheck = true;
  installCheckPhase = ''
    # May need a writable home, seen on Darwin.
    HOME=$TMP $out/bin/pwsh --help > /dev/null
  '';

  meta = with lib; {
    description = "Powerful cross-platform (Windows, Linux, and macOS) shell and scripting language based on .NET";
    homepage = "https://github.com/PowerShell/PowerShell";
    maintainers = with maintainers; [ yrashk srgom ];
    platforms = [ "x86_64-darwin" "x86_64-linux" "aarch64-linux"];
    license = with licenses; [ mit ];
  };

  passthru = {
    shellPath = "/bin/pwsh";
  };

}
