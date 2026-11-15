Name:           luks-root-smartcard-tools
Version:        1.2.1
Release:        1%{?dist}
Summary:        Smartcard root unlock for Fedora/RHEL with dracut
License:        MIT
Homepage:       https://github.com/jtmoree-github-com/luks-root-smartcard
Source0:        https://github.com/jtmoree-github-com/luks-root-smartcard/archive/main.tar.gz

BuildArch:      noarch
BuildRequires:  make

Requires:       cryptsetup
Requires:       dracut
Recommends:     gnupg
Recommends:     opensc
Recommends:     pcscd
Recommends:     systemd
Recommends:     libfido2
Suggests:       bash-completion

%description
Provides dracut modules and boot scripts that unlock the root volume
using a smartcard or TPM. Supports FIDO2 (systemd-fido2), TPM2 (systemd-tpm2),
PKCS#11 (systemd-pkcs11), and GPG/scdaemon (gpg-token or keyfile).

%prep
%autosetup -n luks-root-smartcard-main

%build
# No build needed; scripts are ready to install

%install
# Install dracut modules
mkdir -p %{buildroot}%{_libdir}/dracut/modules.d/
cp -r dracut/* %{buildroot}%{_libdir}/dracut/modules.d/

# Install scripts and libraries
mkdir -p %{buildroot}%{_sbindir}/
mkdir -p %{buildroot}%{_datadir}/%{name}/
cp bin/decomm-boot.sh %{buildroot}%{_sbindir}/
cp bin/rebuild-signed-uki.sh %{buildroot}%{_sbindir}/
cp bin/smartcard-scan %{buildroot}%{_sbindir}/
cp scripts/smartcard-common-lib.sh %{buildroot}%{_datadir}/%{name}/
cp scripts/smartcard-hook-common.sh %{buildroot}%{_datadir}/%{name}/
cp scripts/gpg-cryptenroll %{buildroot}%{_sbindir}/
cp scripts/gpg-cryptopen %{buildroot}%{_sbindir}/
cp scripts/gpg-cryptmount %{buildroot}%{_sbindir}/

# Install bash completion
mkdir -p %{buildroot}%{_datadir}/bash-completion/completions/
cp completion/gpg-cryptenroll %{buildroot}%{_datadir}/bash-completion/completions/

# Install config
mkdir -p %{buildroot}%{_sysconfdir}/%{name}/
cp conf/initramfs.conf %{buildroot}%{_sysconfdir}/%{name}/

%files
%license LICENSE
%doc README.md
%{_libdir}/dracut/modules.d/*
%{_sbindir}/decomm-boot.sh
%{_sbindir}/rebuild-signed-uki.sh
%{_sbindir}/smartcard-scan
%{_sbindir}/gpg-cryptenroll
%{_sbindir}/gpg-cryptopen
%{_sbindir}/gpg-cryptmount
%{_datadir}/%{name}/*.sh
%{_datadir}/bash-completion/completions/gpg-cryptenroll
%config(noreplace) %{_sysconfdir}/%{name}/initramfs.conf

%changelog
* Sat Nov 15 2026 JT Moree <jtmoree@users.noreply.github.com> - 1.2.1-1
- Initial RPM packaging with bin scripts and dracut support
