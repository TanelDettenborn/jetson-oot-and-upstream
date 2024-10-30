{
  nixpkgs ? fetchTarball "https://github.com/NixOS/nixpkgs/archive/a6292e34000dc93d43bccf78338770c1c5ec8a99.tar.gz",
  pkgsNative ? import nixpkgs { },
  pkgsAarch64 ? import nixpkgs {
    system = "aarch64-linux";
  },
}:
let
  linux68_pkg =
    {
      lib,
      fetchurl,
      buildLinux,
      ...
    }@args:
    buildLinux (
      args
      // rec {
        pname = "linux68";
        version = "6.8.12";
        extraMeta.branch = "6.8";

        defconfig = "defconfig";
        autoModules = false;

        src = fetchurl {
          url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/snapshot/linux-6.8.y.tar.gz";
          hash = "sha256-AvGkgpMPUcZ953eoU/joJT5AvPYA4heEP7gpewzdjy8";
        };
        kernelPatches = [ ];

        structuredExtraConfig = with lib.kernel; {
          ARM64_PMEM = yes;
          PCIE_TEGRA194 = yes;
          PCIE_TEGRA194_HOST = yes;
          BLK_DEV_NVME = yes;
          NVME_CORE = yes;
          FB_SIMPLE = yes;
        };

      }
      // (args.argsOverride or { })
    );

  linux68-cross = pkgsNative.pkgsCross.aarch64-multiplatform.callPackage linux68_pkg { };
  linux68-native = pkgsAarch64.callPackage linux68_pkg { };
in
{
  nvidia-oot-cross = pkgsNative.pkgsCross.aarch64-multiplatform.callPackage ./nvidia-oot.nix {
    linux = linux68-cross;
  };
  nvidia-oot-native = pkgsAarch64.callPackage ./nvidia-oot.nix {
    linux = linux68-native;
  };
}
