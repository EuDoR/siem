#!/usr/bin/env bash
set -euo pipefail

# Requisitos: Azure CLI instalado, sesion iniciada con "az login" y permisos
# para crear y eliminar recursos.
# Crear VM con Nginx y Log Analytics: bash ScriptPrueba.sh create
# Crear VM y Event Hubs: bash ScriptPrueba.sh create --event-hub
# Crear ambos: bash ScriptPrueba.sh create --log-analytics --event-hub
# El namespace debe ser unico globalmente. Si ya existe, cambia su nombre:
# EVENTHUB_NAMESPACE=otro-nombre bash ScriptPrueba.sh create --event-hub
# Eliminar: bash ScriptPrueba.sh destroy
# Consultar regiones y politicas: bash ScriptPrueba.sh regions
# Las variables se pueden cambiar al ejecutar el script:
# LOCATION=chilecentral VM_SIZE=Standard_B2ats_v2 bash ScriptPrueba.sh create
# Usar el mismo RESOURCE_GROUP para crear y eliminar.
# Regiones permitidas por la politica consultada: chilecentral, mexicocentral,
# northcentralus, canadacentral y westcentralus. La politica puede cambiar.
#
# La VM no tiene IP publica; requiere acceso privado (VPN, ExpressRoute o
# una maquina intermediaria). Los destinos se crean sin ingesta configurada.
# Los recursos generan cargos; el precio y disponibilidad dependen de la region.
# Event Hubs Basic genera cargos por capacidad aun sin eventos.

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-siem}"
LOCATION="${LOCATION:-northcentralus}"
VM_NAME="${VM_NAME:-vm-siem-linux}"
VM_SIZE="${VM_SIZE:-Standard_B2ats_v2}"
VM_IMAGE="${VM_IMAGE:-Ubuntu2204}"
ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
WORKSPACE_NAME="${WORKSPACE_NAME:-law-siem}"
EVENTHUB_NAMESPACE="${EVENTHUB_NAMESPACE:-ns-siem-artifactory-lab}"
EVENTHUB_NAME="${EVENTHUB_NAME:-eh-siem}"

usage() {
    printf '%-58s | %s\n' "Comando" "Resultado"
    printf '%-58s-+-%s\n' "----------------------------------------------------------" "-----------------------------------------------------------"
    printf '%-58s | %s\n' "./ScriptPrueba.sh create" "Crea la VM con Nginx y Log Analytics."
    printf '%-58s | %s\n' "./ScriptPrueba.sh create --log-analytics" "Crea la VM con Nginx y Log Analytics."
    printf '%-58s | %s\n' "./ScriptPrueba.sh create --event-hub" "Crea la VM con Nginx y Event Hubs."
    printf '%-58s | %s\n' "./ScriptPrueba.sh create --log-analytics --event-hub" "Crea la VM con Nginx, Log Analytics y Event Hubs."
    printf '%-58s | %s\n' "./ScriptPrueba.sh regions" "Consulta regiones y politicas de la suscripcion."
    printf '%-58s | %s\n' "./ScriptPrueba.sh destroy" "Elimina el grupo y TODOS sus recursos, previa confirmacion."
    printf '%-58s | %s\n' "./ScriptPrueba.sh --help" "Muestra esta ayuda."
    echo
    echo "Nginx se instala o verifica en la VM y se genera una solicitud local de prueba."
    echo "Log Analytics no recopila automaticamente los logs de Nginx; configura AMA y una DCR para /var/log/nginx/access.log."
    echo "Los recursos no configuran automaticamente el envio de logs."
    echo "Event Hubs Basic genera cargos aun sin eventos."
    echo "Namespace de Event Hubs: $EVENTHUB_NAMESPACE (debe ser unico globalmente)."
    echo "Si el nombre esta ocupado, define EVENTHUB_NAMESPACE con otro nombre unico."
    echo "Variables: RESOURCE_GROUP, LOCATION, VM_NAME, VM_SIZE, VM_IMAGE, ADMIN_USERNAME, WORKSPACE_NAME, EVENTHUB_NAMESPACE, EVENTHUB_NAME."
    echo "LOCATION por defecto: northcentralus."
    echo "VM_SIZE por defecto: Standard_B2ats_v2 (la disponibilidad puede cambiar)."
    echo "Regiones observadas en la politica: chilecentral, mexicocentral, northcentralus, canadacentral, westcentralus."
    echo "Consulta regions para verificar cambios en las politicas."
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 1
fi

case "$1" in
    create|--create) ACTION=create ;;
    destroy|--destroy) ACTION=destroy ;;
    regions|--regions) ACTION=regions ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: accion desconocida: $1" >&2; usage >&2; exit 1 ;;
esac
shift

CREATE_LOG_ANALYTICS=false
CREATE_EVENT_HUB=false
if [ "$ACTION" = create ]; then
    if [ "$#" -eq 0 ]; then
        CREATE_LOG_ANALYTICS=true
    fi
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --log-analytics) CREATE_LOG_ANALYTICS=true ;;
            --event-hub) CREATE_EVENT_HUB=true ;;
            *) echo "Error: opcion desconocida: $1" >&2; usage >&2; exit 1 ;;
        esac
        shift
    done
elif [ "$#" -ne 0 ]; then
    echo "Error: la accion $ACTION no acepta opciones." >&2
    usage >&2
    exit 1
fi

if ! command -v az >/dev/null 2>&1; then
    echo "Error: instala Azure CLI antes de ejecutar el script." >&2
    exit 1
fi

if ! az account show --output none; then
    echo "Error: inicia sesion con 'az login' y selecciona una suscripcion." >&2
    exit 1
fi

echo "Suscripcion seleccionada:"
az account show --query '{nombre:name,id:id}' --output table

if [ "$ACTION" = regions ]; then
    echo "Catalogo de regiones de Azure (no implica que la politica permita usarlas):"
    az account list-locations \
        --query '[].{nombre:name,region:displayName}' \
        --output table

    echo "Politicas aplicables a la suscripcion y, si existe, al grupo '$RESOURCE_GROUP':"
    group_exists=$(az group exists --name "$RESOURCE_GROUP" --output tsv)
    if [ "$group_exists" = true ]; then
        az policy assignment list \
            --resource-group "$RESOURCE_GROUP" \
            --filter 'atScope()' \
            --output json
    else
        echo "El grupo no existe; se consultaran solo las politicas aplicables a la suscripcion."
        az policy assignment list --filter 'atScope()' --output json
    fi
    echo "Revisa las asignaciones y sus parametros de ubicacion. Algunas restricciones administradas por Azure pueden no aparecer en esta lista."
    echo "La disponibilidad de la VM y del workspace puede variar incluso en regiones permitidas."
    exit 0
fi

if [ "$ACTION" = destroy ]; then
    group_exists=$(az group exists --name "$RESOURCE_GROUP" --output tsv)
    if [ "$group_exists" != true ]; then
        echo "Error: el grupo '$RESOURCE_GROUP' no existe en la suscripcion seleccionada." >&2
        exit 1
    fi

    echo "Grupo de recursos que se eliminara: $RESOURCE_GROUP" >&2
    echo "Recursos que contiene:" >&2
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].{nombre:name,tipo:type}' \
        --output table
    echo "ADVERTENCIA: se eliminara '$RESOURCE_GROUP' y TODOS sus recursos, incluso los no creados por este script." >&2
    printf "Escribe exactamente '%s' para confirmar: " "$RESOURCE_GROUP" >&2
    if ! IFS= read -r confirmation; then
        echo "Error: no se recibio la confirmacion. No se elimino ningun recurso." >&2
        exit 1
    fi
    if [ "$confirmation" != "$RESOURCE_GROUP" ]; then
        echo "Confirmacion incorrecta. No se elimino ningun recurso." >&2
        exit 1
    fi
    echo "Eliminando el grupo de recursos '$RESOURCE_GROUP'..."
    az group delete --name "$RESOURCE_GROUP" --yes --output none
    echo "Grupo de recursos eliminado."
    exit 0
fi

echo "Region: ${LOCATION}; grupo: ${RESOURCE_GROUP}; tamano de VM: ${VM_SIZE}"

group_exists=$(az group exists --name "$RESOURCE_GROUP" --output tsv)
if [ "$group_exists" = true ]; then
    echo "El grupo '$RESOURCE_GROUP' ya existe; se reutilizara sin cambiar su ubicacion."
    echo "Los recursos nuevos se crearan en $LOCATION."
else
    echo "Creando grupo de recursos..."
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output none
fi

vm_names=$(az vm list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
if printf '%s\n' "$vm_names" | grep -Fxq -- "$VM_NAME"; then
    echo "La VM '$VM_NAME' ya existe; se reutilizara sin modificarla."
else
    echo "Creando VM Linux sin IP publica..."
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --location "$LOCATION" \
        --image "$VM_IMAGE" \
        --size "$VM_SIZE" \
        --admin-username "$ADMIN_USERNAME" \
        --authentication-type ssh \
        --generate-ssh-keys \
        --public-ip-address "" \
        --nsg-rule NONE \
        --security-type Standard \
        --storage-sku Standard_LRS \
        --os-disk-size-gb 30 \
        --output none
fi

echo "Instalando/verificando Nginx y generando una solicitud local de prueba..."
if ! nginx_result=$(az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts 'set -e; apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y nginx curl; systemctl enable --now nginx; systemctl is-active --quiet nginx; curl --fail --silent --show-error --max-time 10 --output /dev/null "http://127.0.0.1/?prueba-siem=instalacion"; test -s /var/log/nginx/access.log; printf "\nSIEM_NGINX_INSTALADO_OK\n"' \
    --query 'value[].message' \
    --output tsv); then
    echo "Error: Azure Run Command fallo. La VM y otros recursos existentes permanecen en '$RESOURCE_GROUP'." >&2
    exit 1
fi

if ! printf '%s\n' "$nginx_result" | grep -Fxq 'SIEM_NGINX_INSTALADO_OK'; then
    echo "Error: no se pudo confirmar la instalacion y prueba de Nginx en la VM." >&2
    printf '%s\n' "$nginx_result" >&2
    echo "La VM y otros recursos existentes permanecen en '$RESOURCE_GROUP'." >&2
    exit 1
fi
echo "Nginx esta activo y la solicitud de prueba fue registrada en /var/log/nginx/access.log."

if [ "$CREATE_LOG_ANALYTICS" = true ]; then
    workspace_names=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    if printf '%s\n' "$workspace_names" | grep -Fxq -- "$WORKSPACE_NAME"; then
        echo "El workspace '$WORKSPACE_NAME' ya existe; se reutilizara sin modificarlo."
    else
        echo "Creando workspace de Log Analytics..."
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$WORKSPACE_NAME" \
            --location "$LOCATION" \
            --sku PerGB2018 \
            --retention-time 30 \
            --output none
    fi
fi

if [ "$CREATE_EVENT_HUB" = true ]; then
    namespace_names=$(az eventhubs namespace list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    if printf '%s\n' "$namespace_names" | grep -Fxq -- "$EVENTHUB_NAMESPACE"; then
        echo "El namespace '$EVENTHUB_NAMESPACE' ya existe; se reutilizara sin modificarlo."
    else
        echo "Creando namespace Event Hubs Basic (genera cargos por capacidad)..."
        az eventhubs namespace create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$EVENTHUB_NAMESPACE" \
            --location "$LOCATION" \
            --sku Basic \
            --capacity 1 \
            --output none
    fi
    eventhub_names=$(az eventhubs eventhub list --resource-group "$RESOURCE_GROUP" --namespace-name "$EVENTHUB_NAMESPACE" --query '[].name' --output tsv)
    if printf '%s\n' "$eventhub_names" | grep -Fxq -- "$EVENTHUB_NAME"; then
        echo "El Event Hub '$EVENTHUB_NAME' ya existe; se reutilizara sin modificarlo."
    else
        echo "Creando Event Hub..."
        az eventhubs eventhub create \
            --resource-group "$RESOURCE_GROUP" \
            --namespace-name "$EVENTHUB_NAMESPACE" \
            --name "$EVENTHUB_NAME" \
            --partition-count 2 \
            --message-retention 1 \
            --output none
    fi
fi

echo "Recursos creados:"
echo "Grupo de recursos: $RESOURCE_GROUP"
az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --show-details \
    --query '{vm:name,ipPrivada:privateIps,estado:powerState}' \
    --output table
if [ "$CREATE_LOG_ANALYTICS" = true ]; then
    az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query '{workspace:name,id:id}' \
        --output table
    echo "Log Analytics no recibe logs automaticamente: configura AMA y una DCR para /var/log/nginx/access.log."
fi
if [ "$CREATE_EVENT_HUB" = true ]; then
    az eventhubs eventhub show \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$EVENTHUB_NAMESPACE" \
        --name "$EVENTHUB_NAME" \
        --query '{eventHub:name,id:id}' \
        --output table
    echo "Event Hubs no recibe logs automaticamente; configura un mecanismo de envio."
fi

echo "Para detener los cargos de computo cuando no uses la VM: az vm deallocate --resource-group \"$RESOURCE_GROUP\" --name \"$VM_NAME\""
echo "El disco y otros recursos pueden seguir generando cargos."