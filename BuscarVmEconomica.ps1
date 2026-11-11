# Compara SKU Linux economicos sin crear recursos.
# Requisitos: PowerShell, Azure CLI, az login y acceso a prices.azure.com.
# Ejecutar: .\BuscarVmEconomica.ps1
# Las regiones provienen de la politica consultada; esta puede cambiar.

$ErrorActionPreference = 'Stop'
$regiones = @('chilecentral', 'mexicocentral', 'northcentralus', 'canadacentral', 'westcentralus')
$tamanos = @(
    'Standard_B1ls', 'Standard_B1s', 'Standard_B1ms', 'Standard_B2s',
    'Standard_B2ms', 'Standard_B2ls_v2', 'Standard_B2s_v2', 'Standard_B2ms_v2',
    'Standard_B2als_v2', 'Standard_B2as_v2', 'Standard_B2ats_v2'
)

function Invoke-AzJson {
    param([string[]] $Argumentos)

    $resultado = & az @Argumentos --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI fallo al ejecutar: az $($Argumentos -join ' ')"
    }
    return ($resultado | Out-String | ConvertFrom-Json)
}

function Get-Precios {
    param([string] $Region)

    $filtroSku = ($tamanos | ForEach-Object { "armSkuName eq '$_'" }) -join ' or '
    $filtro = "serviceName eq 'Virtual Machines' and armRegionName eq '$Region' and priceType eq 'Consumption' and ($filtroSku)"
    $url = 'https://prices.azure.com/api/retail/prices?currencyCode=USD&$filter=' + [uri]::EscapeDataString($filtro)
    $precios = @{}
    while ($url) {
        $pagina = Invoke-RestMethod -Uri $url -TimeoutSec 30
        foreach ($item in $pagina.Items) {
            $nombre = "$($item.productName) $($item.skuName) $($item.meterName)"
            if ($item.armSkuName -notin $tamanos -or
                $item.armRegionName -ne $Region -or
                $item.currencyCode -ne 'USD' -or
                $item.type -ne 'Consumption' -or
                $item.unitOfMeasure -ne '1 Hour' -or
                $item.tierMinimumUnits -ne 0 -or
                $nombre -match 'Windows|Spot|Low Priority') {
                continue
            }
            $precio = [decimal] $item.retailPrice
            $fecha = [DateTimeOffset]::Parse($item.effectiveStartDate)
            if ($precio -le 0 -or $fecha -gt [DateTimeOffset]::UtcNow) {
                continue
            }
            $anterior = $precios[$item.armSkuName]
            if ($null -eq $anterior -or $fecha -gt $anterior.Fecha -or
                ($fecha -eq $anterior.Fecha -and $precio -lt $anterior.Precio)) {
                $precios[$item.armSkuName] = @{ Fecha = $fecha; Precio = $precio }
            }
        }
        $url = $pagina.NextPageLink
    }
    return $precios
}

try {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'No se encontro Azure CLI. Instala az e inicia sesion con az login.'
    }
    $cuenta = Invoke-AzJson @('account', 'show')
    Write-Host "Suscripcion: $($cuenta.name) ($($cuenta.id))"
    Write-Host 'Consultando SKU y precios; esto puede tardar unos minutos.'

    $candidatos = @()
    $restringidos = @()
    $sinPrecio = @()
    foreach ($region in $regiones) {
        Write-Host "Consultando $region..."
        $skus = @(Invoke-AzJson @('vm', 'list-skus', '--location', $region, '--size', 'Standard_B', '--all'))
        $precios = Get-Precios $region
        $encontrados = @()
        foreach ($sku in $skus) {
            if ($sku.resourceType -ne 'virtualMachines' -or $sku.name -notin $tamanos) {
                continue
            }
            $encontrados += $sku.name
            if (@($sku.restrictions).Count -gt 0 -and $null -ne $sku.restrictions) {
                $motivos = ($sku.restrictions | ForEach-Object { "$($_.type): $($_.reasonCode)" }) -join '; '
                $restringidos += [pscustomobject]@{ Region = $region; Tamano = $sku.name; Motivos = $motivos }
            }
            elseif (-not $precios.ContainsKey($sku.name)) {
                $sinPrecio += [pscustomobject]@{ Region = $region; Tamano = $sku.name }
            }
            else {
                $precio = $precios[$sku.name].Precio
                $candidatos += [pscustomobject]@{
                    Region = $region
                    Tamano = $sku.name
                    USDHora = $precio
                    USD730Horas = [math]::Round($precio * 730, 2)
                }
            }
        }
        $ausentes = @($tamanos | Where-Object { $_ -notin $encontrados })
        if ($ausentes.Count -gt 0) {
            Write-Host "${region}: SKU no listados: $($ausentes -join ', ')"
        }
    }

    $candidatos = @($candidatos | Sort-Object USDHora, Region, Tamano)
    Write-Host "`nCandidatos sin restricciones reportadas, ordenados por precio publico:"
    if ($candidatos.Count -gt 0) {
        $candidatos | Format-Table Region, Tamano, USDHora, USD730Horas -AutoSize
    }
    else {
        Write-Host 'No se encontraron candidatos con precio y sin restricciones reportadas.'
    }
    if ($restringidos.Count -gt 0) {
        Write-Host "`nSKU excluidos por restricciones reportadas, incluidas las de zona:"
        $restringidos | Format-Table -AutoSize
    }
    if ($sinPrecio.Count -gt 0) {
        Write-Host "`nSKU excluidos porque no se encontro precio publico Linux por hora:"
        $sinPrecio | Format-Table -AutoSize
    }

    Write-Host 'IMPORTANTE: sin restricciones no significa capacidad garantizada.'
    Write-Host 'Politicas, cuotas, compatibilidad de imagen y capacidad se comprueban al desplegar.'
    Write-Host 'Precios publicos de computo en USD, sin descuentos, disco, red ni impuestos; 730 horas al mes.'
    if ($candidatos.Count -eq 0) {
        exit 1
    }
    $mejor = $candidatos[0]
    Write-Host "`nPara probar el candidato mas barato en Git Bash:"
    Write-Host "LOCATION=$($mejor.Region) VM_SIZE=$($mejor.Tamano) ./ScriptPrueba.sh create"
}
catch {
    Write-Error "Error al consultar Azure: $_"
    exit 1
}
