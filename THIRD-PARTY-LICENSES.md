# Third-party licenses

The MIT licence in [LICENSE](LICENSE) covers the scripts, patches and documentation authored in this repository. It does not cover Transmission.

## Transmission

Transmission is licensed under the GNU General Public License, GPLv2 or GPLv3 at the recipient's option, with some files carrying additional permissive licences. See the `licenses/` directory of the upstream source for the authoritative text.

Upstream project: <https://github.com/transmission/transmission>

### What this repository distributes

Release artifacts include a compiled `transmission-daemon` binary. That binary is a modified version of Transmission, so the GPL requires that the corresponding source accompany it. Both parts are published here:

| Part | Where |
|---|---|
| Unmodified upstream source | Fetched at build time from the official release tarball named in [build/build-in-container.sh](build/build-in-container.sh) |
| The modification | [patches/0001-honor-downloadstation-task-id.patch](patches/0001-honor-downloadstation-task-id.patch) |
| The exact build recipe | [build/build.sh](build/build.sh) and [build/build-in-container.sh](build/build-in-container.sh) |

Applying the patch to the named upstream release and running the build recipe reproduces the distributed binary. Nothing in the build depends on a private source tree.

### Statically linked components

The binary statically links Transmission's bundled third-party libraries so it depends only on shared objects DSM already provides. Each retains its own licence as distributed in the upstream tarball:

| Component | Licence |
|---|---|
| libevent | 3-clause BSD |
| libdeflate | MIT |
| libpsl | MIT |
| libb64 | Public domain / CC0 |
| dht | MIT |
| libutp | MIT |
| libnatpmp | 3-clause BSD |
| miniupnpc | 3-clause BSD |
| fmt | MIT |
| rapidjson | MIT |
| utfcpp | Boost Software License 1.0 |
| wide-integer | Boost Software License 1.0 |
| small | MIT |
| fast_float | Apache-2.0 / MIT / BSL-1.0 |

`libstdc++` and `libgcc` are linked statically under the GCC Runtime Library Exception, which permits distribution of the resulting binary without imposing GPL terms on this repository's own code.

## Trademarks

Synology, DiskStation and DownloadStation are trademarks of Synology Inc. This project is not affiliated with, endorsed by, or supported by Synology or the Transmission project.
