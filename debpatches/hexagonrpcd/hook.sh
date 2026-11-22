# hexagonrpcd 0.5.0 on Debian's 0.4 packaging: upstream now installs one
# service per DSP; Debian keeps its single hexagonrpcd.service (configured per
# device with a drop-in), so leave the upstream units out.
cat >> debian/not-installed <<'EOF'
usr/lib/*/systemd/system/hexagonrpcd-adsp-rootpd.service
usr/lib/*/systemd/system/hexagonrpcd-adsp-sensorspd.service
usr/lib/*/systemd/system/hexagonrpcd-sdsp.service
EOF

# sscregistrygen (pmOS: hexagonrpcd-tools) is built but not installed by
# upstream; oneplus-ota-fetch/setup-sensors need it to build the sensor registry
echo "obj-*/tools/sscregistrygen usr/bin" >> debian/hexagonrpcd.install
