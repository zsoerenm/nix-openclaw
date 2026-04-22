{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  nodejs_22,
  pnpm_10,
  fetchPnpmDeps,
  pkg-config,
  jq,
  python3,
  perl,
  node-gyp,
  makeWrapper,
  vips,
  git,
  zstd,
  sourceInfo,
  gatewaySrc ? null,
  pnpmDepsHash ? (sourceInfo.pnpmDepsHash or null),
}:

assert gatewaySrc == null || pnpmDepsHash != null;

let
  # Matrix SDK crypto native binaries for E2E encryption support.
  # The @matrix-org/matrix-sdk-crypto-nodejs package downloads a platform-specific
  # .node binary at runtime via node-downloader-helper, which fails in Nix
  # because the store is read-only. Fetch the binary at eval time and install
  # it into the package directory so the runtime finds it.
  # Version must match @matrix-org/matrix-sdk-crypto-nodejs in upstream pnpm-lock.yaml.
  matrixCryptoVersion = "0.4.0";
  matrixCryptoLib = fetchurl (
    if stdenv.hostPlatform.isDarwin then
      if stdenv.hostPlatform.isAarch64 then {
        url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v${matrixCryptoVersion}/matrix-sdk-crypto.darwin-arm64.node";
        hash = "sha256-9/X99ikki9q5NOUDj3KL+7OzYfOhSiTtGAZhCMEpry8=";
      } else {
        url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v${matrixCryptoVersion}/matrix-sdk-crypto.darwin-x64.node";
        hash = "sha256-gXCIiuSW2YNpeSvK0G+bdlOCFNkvjqCmOecB9UBe/Ss=";
      }
    else
      if stdenv.hostPlatform.isAarch64 then {
        url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v${matrixCryptoVersion}/matrix-sdk-crypto.linux-arm64-gnu.node";
        hash = "sha256-DcHFgxVYDNDO85wuHsKOHjiFajN28ll9oa4gOI8k0PQ=";
      } else {
        url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v${matrixCryptoVersion}/matrix-sdk-crypto.linux-x64-gnu.node";
        hash = "sha256-cHjU3ZhxKPea/RksT2IfZK3s435D8qh1bx0KnwNN5xg=";
      }
  );

  matrixCryptoFilename =
    if stdenv.hostPlatform.isDarwin then
      if stdenv.hostPlatform.isAarch64 then "matrix-sdk-crypto.darwin-arm64.node"
      else "matrix-sdk-crypto.darwin-x64.node"
    else
      if stdenv.hostPlatform.isAarch64 then "matrix-sdk-crypto.linux-arm64-gnu.node"
      else "matrix-sdk-crypto.linux-x64-gnu.node";

  common =
    import ../lib/openclaw-gateway-common.nix
      {
        inherit
          lib
          stdenv
          fetchFromGitHub
          fetchurl
          nodejs_22
          pnpm_10
          fetchPnpmDeps
          pkg-config
          jq
          python3
          node-gyp
          git
          zstd
          ;
      }
      {
        pname = "openclaw-gateway";
        sourceInfo = sourceInfo;
        pnpmDepsHash = pnpmDepsHash;
        pnpmDepsPname = "openclaw-gateway";
        gatewaySrc = gatewaySrc;
        enableSharp = true;
        extraNativeBuildInputs = [
          perl
          makeWrapper
        ];
        extraBuildInputs = [ vips ];
        extraEnv = {
          NODE_BIN = "${nodejs_22}/bin/node";
          PATCH_CLIPBOARD_SH = "${../scripts/patch-clipboard.sh}";
          PATCH_CLIPBOARD_WRAPPER = "${../scripts/clipboard-wrapper.cjs}";
          MATRIX_CRYPTO_LIB = matrixCryptoLib;
          MATRIX_CRYPTO_LIB_FILENAME = matrixCryptoFilename;
        };
      };

in

stdenv.mkDerivation (finalAttrs: {
  pname = "openclaw-gateway";
  inherit (common) version;

  src = common.resolvedSrc;
  pnpmDeps = common.pnpmDeps;

  nativeBuildInputs = common.nativeBuildInputs;
  buildInputs = common.buildInputs;

  env = common.env // {
    # Nix doesn't automatically substitute finalAttrs into env.
    PNPM_DEPS = finalAttrs.pnpmDeps;
  };

  passthru = common.passthru;

  postPatch = "${../scripts/gateway-postpatch.sh}";
  buildPhase = "${../scripts/gateway-build.sh}";
  installPhase = "${../scripts/gateway-install.sh}";
  dontFixup = true;
  dontStrip = true;
  dontPatchShebangs = true;

  meta = with lib; {
    description = "Telegram-first AI gateway (OpenClaw)";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin ++ platforms.linux;
    mainProgram = "openclaw";
  };
})
