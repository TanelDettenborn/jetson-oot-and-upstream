# shell.nix
#
{
  nixpkgs ? fetchTarball "https://github.com/NixOS/nixpkgs/archive/a6292e34000dc93d43bccf78338770c1c5ec8a99.tar.gz",
}:
let
  hostPkgs = import <nixpkgs> {};
  pkgs = import nixpkgs { crossSystem.config = "aarch64-linux-gnu"; };
  buildPackages = pkgs.buildPackages;

  # Replicates Jetpack-nixos kernel
  linux68_pkg = { lib, fetchurl, buildLinux, ... } @ args:

    buildLinux (args // rec {
      pname = "linux68";
      version = "6.8.12";
      extraMeta.branch = "6.8";

      defconfig = "defconfig";
      autoModules = false;

      src = fetchurl {
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/snapshot/linux-6.8.y.tar.gz";
        hash = "sha256-AvGkgpMPUcZ953eoU/joJT5AvPYA4heEP7gpewzdjy8";
      };
      kernelPatches = [];

      structuredExtraConfig = with lib.kernel; {
        ARM64_PMEM = yes;
        PCIE_TEGRA194 = yes;
        PCIE_TEGRA194_HOST = yes;
        BLK_DEV_NVME = yes;
        NVME_CORE = yes;
        FB_SIMPLE = yes;
      };

    } // (args.argsOverride or {}));

  linux68 = pkgs.callPackage linux68_pkg{};

  nvidia-oot = pkgs.stdenv.mkDerivation rec {
    pname = "oot-modules";
    version = "6.8.12";

    src = pkgs.fetchurl {
      url = "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/sources/public_sources.tbz2";
      hash = "sha256-6U2+ACWuMT7rYDBhaXr+13uWQdKgbfAiiIV0Vi3R9sU=";
    };

    nativeBuildInputs = linux68.moduleBuildDependencies ++ [
      # pkgs.breakpointHook
    ];

    configurePhase = ''
      runHook preConfigure

      cd source

      tar xf kernel_oot_modules_src.tbz2
      tar xf nvidia_kernel_display_driver_source.tbz2

      export CROSS_COMPILE=${pkgs.stdenv.cc}/bin/${pkgs.stdenv.cc.targetPrefix}
      export KERNEL_HEADERS=${linux68.dev}/lib/modules/${linux68.modDirVersion}/build
      export IGNORE_MISSING_MODULE_SYMVERS=1

      # Patch nvidia modules source
      sed -i '49s/SOURCES=$(KERNEL_HEADERS)/SOURCES=$(KERNEL_HEADERS)\/source/g' Makefile
      sed -i '/cp -LR $(KERNEL_HEADERS)\/\* $(NVIDIA_HEADERS)/s/$/ \|\| true;/' Makefile
      #Sources are copied from store. They are read only
      sed -i '/cp -LR $(KERNEL_HEADERS)\/\* $(NVIDIA_HEADERS)/a \\tchmod -R u+w out/nvidia-linux-header/' Makefile
      sed -i '113s/SYSSRC=$(NVIDIA_HEADERS)/SYSSRC=$(NVIDIA_HEADERS)\/source/g' Makefile
      # TODO: Remove warning:
      #    warning: call to ‘__write_overflow_field’
      sed -i '/subdir-ccflags-y += -Werror/d' nvidia-oot/Makefile

      runHook postConfigure
    '';
    buildPhase = ''
      runHook preBuild

      make modules

      runHook postBuild
    '';

    # Avoid an error in modpost: "__stack_chk_guard" [.../nvidia.ko] undefined
    NIX_CFLAGS_COMPILE = "-fno-stack-protector";

    installTargets = [ "modules_install" ];
    enableParallelBuilding = true;
  };

  compile_nvidia_modules = pkgs.writeShellScriptBin "prepare_and_compile_modules" ''

    # Download Jetson BSP and unpack
    wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/sources/public_sources.tbz2
    tar xf public_sources.tbz2

    # CD into source!
    cd Linux_for_Tegra/source

    # Unpack nvidia modules
    tar xf kernel_oot_modules_src.tbz2
    tar xf nvidia_kernel_display_driver_source.tbz2

    # Patch nvidia modules source
    sed -i '49s/SOURCES=$(KERNEL_HEADERS)/SOURCES=$(KERNEL_HEADERS)\/source/g' Makefile
    sed -i '/cp -LR $(KERNEL_HEADERS)\/\* $(NVIDIA_HEADERS)/s/$/ \|\| true;/' Makefile
    #Sources are copied from store. They are read only
    sed -i '/cp -LR $(KERNEL_HEADERS)\/\* $(NVIDIA_HEADERS)/a \\tchmod -R u+w out/nvidia-linux-header/' Makefile
    sed -i '113s/SYSSRC=$(NVIDIA_HEADERS)/SYSSRC=$(NVIDIA_HEADERS)\/source/g' Makefile
    # TODO: Remove warning:
    #    warning: call to ‘__write_overflow_field’
    sed -i '/subdir-ccflags-y += -Werror/d' nvidia-oot/Makefile

    make modules
  '';

  nvidia-oot-raw = derivation {
    name = "nvidia-oot-raw";
    builder = "${hostPkgs.bash}/bin/bash";
    linux68dev =  "${linux68.dev}";
    aarch64LinuxGnu = "${pkgs.stdenv.cc}";
    system = builtins.currentSystem;
    args = [ ./nvidia-oot-builder.sh ];
    src = pkgs.fetchurl {
      url = "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/sources/public_sources.tbz2";
      hash = "sha256-6U2+ACWuMT7rYDBhaXr+13uWQdKgbfAiiIV0Vi3R9sU=";
    };

    buildInputs = [
      hostPkgs.bzip2
      hostPkgs.which
      hostPkgs.gnutar
      hostPkgs.gnumake
      hostPkgs.coreutils
      hostPkgs.gnused
      hostPkgs.binutils.bintools
      hostPkgs.findutils
      hostPkgs.bash
      hostPkgs.gawk
      hostPkgs.gcc
      hostPkgs.gnugrep
      hostPkgs.xz
    ];
  };

in
pkgs.mkShell rec {

  nativeBuildInputs = [
    buildPackages.stdenv.cc
    buildPackages.bash
    buildPackages.flex
    buildPackages.bison
    buildPackages.bc
    buildPackages.lzop
    buildPackages.ncurses
    buildPackages.openssl
    linux68
    compile_nvidia_modules
    # TODO Fix: nvidia-oot
    nvidia-oot-raw
  ];
  shellHook = ''
    export LINUX68=${linux68}
    export LINUX68dev=${linux68.dev}
    export KERNEL_HEADERS=${linux68.dev}/lib/modules/6.8.12/build
    export IGNORE_MISSING_MODULE_SYMVERS=1
    export CROSS_COMPILE=${pkgs.stdenv.cc}/bin/aarch64-linux-gnu-
    export PKG_CONFIG_PATH="${pkgs.ncurses.dev}/lib/pkgconfig:"
    export ARCH=arm64

    echo "#"
    echo "# Following env variables are set"
    echo "#"
    echo LINUX68=$LINUX68
    echo LINUX68dev=$LINUX68dev
    echo KERNEL_HEADERS=$KERNEL_HEADERS
    echo ARCH=$ARCH
    echo CROSS_COMPILE=$CROSS_COMPILE
    echo ""
    echo ""
    echo "#"
    echo "# *NOTE/WARN*: Run \"prepare_and_compile_modules\"-script only ONCE!!"
    echo "# *NOTE/WARN*: Script contains sed-patching and it might mess up sources"
    echo "#"
    echo "# Main compile command: make modules"
    echo "#"
'';

}
