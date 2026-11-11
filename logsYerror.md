$ az vm run-command invoke \
  --resource-group "rg-siem" \
  --name "vm-siem-linux" \
  --command-id RunShellScript \
  --scripts 'echo "=== Procesos AMA ==="; ps -eo user,group,args | grep -E "[m]dsd|[f]luent-bit"; echo "=== Permisos de la ruta ==="; namei -l /var/log/nginx/access.log; echo "=== Ruta en configuracion ==="; grep -lF "/var/log/nginx/access.log" /etc/opt/microsoft/azuremonitoragent/config-cache/configchunks/* || echo "No se encontro la ruta literal"; echo "=== Errores recientes de AMA ==="; tail -n 20 /var/opt/microsoft/azuremonitoragent/log/mdsd.err' \
  --query "value[].message" \
  --output tsv
Enable succeeded: 
[stdout]
=== Procesos AMA ===
syslog   syslog   /opt/microsoft/azuremonitoragent/bin/mdsd -A -R -c /etc/opt/microsoft/azuremonitoragent/mdsd.xml -r /run/azuremonitoragent/default -S /var/opt/microsoft/azuremonitoragent/eh -L /var/opt/microsoft/azuremonitoragent/events
root     root     /opt/microsoft/azuremonitoragent/bin/agentlauncher --fluentBitPath /opt/microsoft/azuremonitoragent/bin/fluent-bit --agentLauncherLogFilePath /var/opt/microsoft/azuremonitoragent/log/agentlauncher.log --agentLauncherStateFilePath /var/opt/microsoft/azuremonitoragent/log/agentlauncher.state.log
root     root     /opt/microsoft/azuremonitoragent/bin/fluent-bit -c /etc/opt/microsoft/azuremonitoragent/config-cache/fluentbit/td-agent.conf
=== Permisos de la ruta ===
f: /var/log/nginx/access.log
drwxr-xr-x root     root   /
drwxr-xr-x root     root   var
drwxrwxr-x root     syslog log
drwxr-xr-x root     adm    nginx
-rw-r----- www-data adm    access.log
=== Ruta en configuracion ===
/etc/opt/microsoft/azuremonitoragent/config-cache/configchunks/16846885047486866107.json
=== Errores recientes de AMA ===
2026-11-11T17:16:50.0933770Z: [DAEMON] Parent process 2151 exit. child process id=2192
2026-11-11T17:16:50.0951730Z: [DAEMON] START mdsd daemon ver(1.45.1) pid(2192) uid(104) gid (111)


[stderr]