cp /mnt/nssf/nssf.yaml install/etc/open5gs
sed -i 's|NSSF_IP|'$NSSF_IP'|g' install/etc/open5gs/nssf.yaml
sed -i 's|NRF_IP|'$NRF_IP'|g' install/etc/open5gs/nssf.yaml
sed -i 's|SCP_IP|'$SCP_IP'|g' install/etc/open5gs/nssf.yaml
sed -i 's|NRF_IP|'$NRF_IP'|g' install/etc/open5gs/nssf.yaml
sed -i 's|MAX_NUM_UE|'$MAX_NUM_UE'|g' install/etc/open5gs/nssf.yaml

# Sync docker time
#ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
