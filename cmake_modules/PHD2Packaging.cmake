#=============================================================================
# Copyright 2017, Max Planck Society.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.

# File created by Raffi Enficiaud
#=============================================================================



SET(CPACK_PACKAGE_VERSION_MAJOR "${VERSION_MAJOR}")
SET(CPACK_PACKAGE_VERSION_MINOR "${VERSION_MINOR}")
SET(CPACK_PACKAGE_VERSION_PATCH "${VERSION_PATCH}")
SET(CPACK_PACKAGE_VENDOR "PHD2 team")

string(TIMESTAMP cdate "%Y%m%d%H%M%S" UTC)
site_name(HOST_NAME)

if(WIN32 AND FALSE)
  # Windows installation through CPack is not supported in this project (ISS installer)
  install (TARGETS phd2 RUNTIME DESTINATION .)
  install (FILES ${PHD_COPY_EXTERNAL_ALL} DESTINATION . )
  if (CMAKE_BUILD_TYPE MATCHES Release)
    install (FILES ${PHD_COPY_EXTERNAL_REL} DESTINATION . )
  else()
    install (FILES ${PHD_COPY_EXTERNAL_DBG} DESTINATION . )
  endif()
  install (FILES ${phd_src_dir}/README-PHD2.txt DESTINATION . )
  install (FILES ${phd_src_dir}/PHD2GuideHelp.zip DESTINATION . )
  install (DIRECTORY ${phd_src_dir}/locale DESTINATION . )

  # Make NSIS package
  set(CPACK_GENERATOR "NSIS")
  set(CPACK_PACKAGE_FILE_NAME "phd2-${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}.${cdate}.${HOST_NAME}-win32")
  set(CPACK_PACKAGE_INSTALL_DIRECTORY "PHDGuiding2")
  set(CPACK_NSIS_EXECUTABLES_DIRECTORY .)
  set(CPACK_NSIS_MENU_LINKS "phd2.exe" "PHD Guiding 2")
  set(CPACK_PACKAGE_DESCRIPTION_FILE "${phd_src_dir}/README-PHD2.txt")
  set(CPACK_RESOURCE_FILE_README "${phd_src_dir}/README-PHD2.txt")
  set(CPACK_RESOURCE_FILE_LICENSE "${phd_src_dir}/LICENSE.txt")

endif()

if(UNIX AND NOT APPLE)
  install(TARGETS phd2
          RUNTIME DESTINATION bin)
  configure_file(phd2.sh.in phd2.sh @ONLY)
  install(PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/phd2.sh
          DESTINATION bin
          RENAME phd2)
  install(FILES ${PHD_INSTALL_LIBS}
          DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/phd2/)
  install(FILES ${PHD_PROJECT_ROOT_DIR}/icons/phd2_48.png
          DESTINATION ${CMAKE_INSTALL_PREFIX}/share/pixmaps/
          RENAME "phd2.png")
  install(FILES ${PHD_PROJECT_ROOT_DIR}/phd2.desktop
          DESTINATION ${CMAKE_INSTALL_PREFIX}/share/applications/ )
  install(FILES ${PHD_PROJECT_ROOT_DIR}/phd2.appdata.xml
          DESTINATION ${CMAKE_INSTALL_PREFIX}/share/metainfo/ )

  # Make Debian package
  set(CPACK_GENERATOR "DEB")
  set(CPACK_DEBIAN_PACKAGE_MAINTAINER "PHD2 team https://github.com/OpenPHDGuiding/phd2")

  # Architecture: ask dpkg, which is authoritative. The previous heuristic keyed off
  # CMAKE_SYSTEM_PROCESSOR and only matched "^arm", so aarch64 fell through to the
  # pointer-size test and 64-bit ARM builds were labelled amd64.
  find_program(DPKG_CMD dpkg)
  if(DPKG_CMD)
    execute_process(COMMAND ${DPKG_CMD} --print-architecture
                    OUTPUT_VARIABLE debarch
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm|aarch64)")
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
      set(debarch "arm64")
    else()
      set(debarch "armhf")
    endif()
  elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(debarch "amd64")
  else()
    set(debarch "i386")
  endif()

  # Suite tag. A binary built on one release is not installable on another: the
  # glibc symbol versions differ, and Debian's 64-bit time_t transition renamed the
  # runtime packages (bookworm ships libwxgtk3.2-1, trixie libwxgtk3.2-1t64, and
  # neither suite carries the other's name). So each release needs its own package,
  # tagged so that the tags sort in release order: "~deb12" < "~deb13" and
  # "~ubuntu24.04" < "~ubuntu26.04". Codenames would not sort correctly -- forky is
  # newer than trixie but sorts lower alphabetically.
  set(debsuite "")
  if(EXISTS /etc/os-release)
    file(READ /etc/os-release _os_release)
    string(REGEX MATCH "\nID=\"?([a-z]+)\"?" _ "\n${_os_release}")
    set(_distro_id "${CMAKE_MATCH_1}")
    if(_os_release MATCHES "VERSION_ID=\"?([0-9.]+)\"?")
      set(_distro_ver "${CMAKE_MATCH_1}")
      if(_distro_id STREQUAL "debian")
        # Debian's VERSION_ID is the major release number: 12, 13
        set(debsuite "~deb${_distro_ver}")
      elseif(_distro_id)
        # Ubuntu's is the full YY.MM, and "~ubuntu24.04" matches the convention
        # already used by the PHD2 PPA
        set(debsuite "~${_distro_id}${_distro_ver}")
      endif()
    elseif(_os_release MATCHES "VERSION_CODENAME=\"?([a-z]+)\"?")
      # Debian testing/unstable carry no VERSION_ID
      set(debsuite "~${CMAKE_MATCH_1}")
    endif()
  endif()

  # Flavour tag. A build that includes the binary-only camera vendor SDKs is a
  # different package from a DFSG-clean one but would otherwise be named
  # identically, so the two would overwrite each other. "+nonfree" sorts above the
  # plain version, which is what we want: where both are offered, the one with more
  # camera support wins.
  if(NOT OPENSOURCE_ONLY)
    set(debsuite "${debsuite}+nonfree")
  endif()

  # package name is lowercase short name
  set(CPACK_DEBIAN_PACKAGE_NAME "phd2")
  # architecture use debian terminology
  set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "${debarch}")
  # version control compatible version name < ppa name to allow further upgrade
  set(CPACK_DEBIAN_PACKAGE_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}.${cdate}.0${debsuite}")
  # set version and arch compatible file name
  set(CPACK_PACKAGE_FILE_NAME "phd2_${CPACK_DEBIAN_PACKAGE_VERSION}_${debarch}")

  # Derive runtime dependencies from the built binary instead of hardcoding them.
  # The correct package names vary by suite (the t64 rename above) and by build
  # options (a bundled static INDI client adds libnova and zlib), so a fixed list
  # cannot be right for every target. Deliberately leave CPACK_DEBIAN_PACKAGE_DEPENDS
  # unset so dpkg-shlibdeps is the only source of Depends.
  set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
  if(PHD_INSTALL_LIBS)
    # OPENSOURCE_ONLY=0 ships binary-only vendor camera libraries inside the package.
    # Point dpkg-shlibdeps at them so it treats them as private (shipped alongside
    # the binary) rather than failing to find a providing package.
    set(_phd_private_dirs "")
    foreach(_lib IN LISTS PHD_INSTALL_LIBS)
      get_filename_component(_dir "${_lib}" DIRECTORY)
      list(APPEND _phd_private_dirs "${_dir}")
    endforeach()
    list(REMOVE_DUPLICATES _phd_private_dirs)
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS_PRIVATE_DIRS "${_phd_private_dirs}")
  endif()

  # The INDI client is linked statically, so this is only needed to run a local
  # server; PHD2 can equally connect to one on another machine.
  set(CPACK_DEBIAN_PACKAGE_SUGGESTS "indi-bin")
  set(CPACK_DEBIAN_PACKAGE_DESCRIPTION "PHD2 auto-guiding software")
  # same section as many astronomy packages
  set(CPACK_DEBIAN_PACKAGE_SECTION "education")
  set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
endif()

if(APPLE)
  install(TARGETS phd2 RUNTIME DESTINATION . BUNDLE DESTINATION .)
  set(CPACK_GENERATOR "ZIP" "DragNDrop")
  set(CPACK_PACKAGE_FILE_NAME "phd2-${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}.${cdate}.${HOST_NAME}-Darwin")
endif()

include(CPack)
