{
  lib,
  stdenv,
  fetchFromGitHub,
  clang,
  cmake,
  lit,
  llvm,
  pkg-config,
  spirv-tools,
  pkgs,
}:

let
  llvmMajor = lib.versions.major llvm.version;

  versions = {
    "23" = {
      version = "23.1.3";
      hash = "sha256-uYB1AhKrj2ivswGENhdedR/rzjGkE/QMRJ4FPJOr2Bk=";
    };
    "22" = {
      version = "22.1.8";
      hash = "sha256-EVE6UDUPDPvE67kPIoRQd5raUYkSbM9s3qb3JoLV7fU=";
    };
    "21" = {
      version = "21.1.13";
      hash = "sha256-nIh/g8rDXKL5V2yHyPe+EfoX4Y0gY0JwIXVDpnmSuR8=";
    };
    "20" = {
      version = "20.1.19";
      hash = "sha256-LDdRozpnQPC+wRBxRkXBreOK+290wIFdTBeMTlkjzOs=";
    };
    "19" = {
      version = "19.1.24";
      hash = "sha256-rhWKd+kSQ0HusiEShTwDal8B8KhYLGtPiamyibqoIn8=";
    };
    "18" = {
      version = "18.1.29";
      hash = "sha256-sucHIsSSGCpduXxD+43tbCAI+pcgv9BlGKaAEX7/qaA=";
    };
  };

  branch =
    versions.${llvmMajor} or {
      version = "${llvmMajor}.x.x";
      hash = "";
    };

  # Pinned by spirv-headers-tag.conf in these releases.
  spirvHeaders = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Headers";
    rev = "cb42dec3830d3ac67fa449ecdc0c0f73d5e74498";
    hash = "sha256-hZ2+H9M55rdvu/MZrrOsZCUXDWbLMDMHyUjDWz/1L7I=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "spirv-llvm-translator";
  inherit (branch) version;

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    # A failed fetch otherwise reports the derivation name "source".
    name = "spirv-llvm-translator-${finalAttrs.version}-source";
    owner = "KhronosGroup";
    repo = "SPIRV-LLVM-Translator";
    tag = "v${finalAttrs.version}";
    hash = branch.hash;
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    llvm.dev
  ];

  buildInputs = [
    llvm
    spirv-tools
  ];

  nativeCheckInputs = [
    clang
    lit
    llvm
    spirv-tools
  ];

  cmakeFlags = [
    (lib.cmakeBool "LLVM_INCLUDE_TESTS" finalAttrs.doCheck)
    # llvm-config is not installed next to the other LLVM tools.
    (lib.cmakeBool "SPIRV_SKIP_DEBUG_INFO_TESTS" true)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "LLVM_SPIRV_BUILD_EXTERNAL" true)
    # RPATH of bin/llvm-spirv contains a forbidden reference to /build.
    (lib.cmakeBool "CMAKE_SKIP_BUILD_RPATH" true)
    (lib.cmakeFeature "LLVM_DIR" "${llvm.dev}")
    # CMake runs this file with Python. The bin/lit wrapper is a shell script.
    (lib.cmakeFeature "LLVM_EXTERNAL_LIT" "${lit}/bin/.lit-wrapped")
    (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${spirvHeaders}")
  ]
  ++ lib.optionals (lib.toInt llvmMajor >= 19) [
    (lib.cmakeFeature "BASE_LLVM_VERSION" "${lib.versions.majorMinor llvm.version}.0")
  ];

  # Lit suite runs only for the default LLVM, and only when the host can run it.
  doCheck = llvm == pkgs.llvm && stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  checkTarget = "check-llvm-spirv";

  # Validation failures with spirv-tools 1.4.363.0.
  env.LIT_FILTER_OUT = lib.concatStringsSep "|" [
    "cooperative_matrix_constant_null.spvasm"
    "llvm-intrinsics/lifetime.ll"
    "llvm-intrinsics/memmove.ll"
    "transcoding/OpenCL/convert_functions.ll"
    "transcoding/constant-vars.ll"
    "transcoding/global_block.cl"
    "type-scavenger/globals.ll"
  ];

  makeFlags = [
    "all"
    "llvm-spirv"
  ];

  postInstall = ''
    install -D tools/llvm-spirv/llvm-spirv $out/bin/llvm-spirv
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    install_name_tool $out/bin/llvm-spirv \
      -change @rpath/libLLVMSPIRVLib.dylib $out/lib/libLLVMSPIRVLib.dylib
  '';

  passthru.tests = lib.genAttrs (lib.attrNames versions) (
    version:
    (pkgs.spirv-llvm-translator.override {
      llvm = pkgs."llvmPackages_${version}".llvm;
    }).overrideAttrs
      (_: {
        # Avoid recursively exposing the same build tests on every variant.
        passthru.tests = { };
      })
  );

  meta = {
    description = "Tool and a library for bi-directional translation between SPIR-V and LLVM IR";
    homepage = "https://github.com/KhronosGroup/SPIRV-LLVM-Translator";
    license = lib.licenses.ncsa;
    maintainers = with lib.maintainers; [ iamanaws ];
    mainProgram = "llvm-spirv";
    platforms = lib.platforms.unix;
    broken = !(versions ? ${llvmMajor});
  };
})
