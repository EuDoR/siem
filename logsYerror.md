az monitor data-collection rule create \
  --resource-group "$RG" \
  --name "$DCR" \
  --location "$LOCATION" \
  --rule-file dcr-nginx.json
Preview version of extension is disabled by default for extension installation, enabled for modules without stable versions. 
Please run 'az config set extension.dynamic_install_allow_preview=true or false' to config it specifically. 
The command requires the extension monitor-control-service. Do you want to install it now? The command will continue to run after the extension is installed. (Y/n): Y
Run 'az config set extension.use_dynamic_install=yes_without_prompt' to allow installing extensions without prompt.
(LinkedInvalidPropertyId) Property id 'C:/Program Files/Git/subscriptions/725cc3de-3af7-492a-a760-300981b7ec0f/resourceGroups/rg-siem/providers/Microsoft.OperationalInsights/workspaces/law-siem2' at path 'properties.destinations.logAnalytics[0].workspaceResourceId' is invalid. Expect fully qualified resource Id that start with '/subscriptions/{subscriptionId}' or '/providers/{resourceProviderNamespace}/'.
Code: LinkedInvalidPropertyId
Message: Property id 'C:/Program Files/Git/subscriptions/725cc3de-3af7-492a-a760-300981b7ec0f/resourceGroups/rg-siem/providers/Microsoft.OperationalInsights/workspaces/law-siem2' at path 'properties.destinations.logAnalytics[0].workspaceResourceId' is invalid. Expect fully qualified resource Id that start with '/subscriptions/{subscriptionId}' or '/providers/{resourceProviderNamespace}/'.