{ stdenv
, lib
, fetchFromGitHub
, makeWrapper
, coreutils
, libnotify
}:

stdenv.mkDerivation {
  pname = "pomo-sh";
  version = "unstable-2023-01-26";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -Dm755 pomo.sh $out/bin/pomo

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/pomo --prefix PATH : ${lib.makeBinPath [ coreutils libnotify ]}
  '';

  meta = {
    description = "A simple Pomodoro timer written in Bash";
    homepage = "https://github.com/stelcodes/pomo";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    maintainers = [ ];
    mainProgram = "pomo";
  };
}
