param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [string]$Size = "1024x1024",

    [int]$Count = 1,

    [string]$OutputDir = "",

    [string]$FileName,

    [string[]]$ReferenceImages,

    [string]$Model = "gpt-image-2",

    [string]$Quality = "auto",

    [string]$BaseUrl = "",

    [string]$ApiKey = "",

    [switch]$Async
)

Add-Type -AssemblyName System.Net.Http

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not $ApiKey) {
    $ApiKey = $env:OPENAI_API_KEY
}

if (-not $ApiKey) {
    throw "OPENAI_API_KEY is not set and -ApiKey was not provided"
}

if (-not $BaseUrl) {
    $BaseUrl = $env:OPENAI_BASE_URL
}

if (-not $BaseUrl) {
    throw "OPENAI_BASE_URL is not set and -BaseUrl was not provided"
}

$BaseUrl = $BaseUrl.TrimEnd('/')

if (-not $OutputDir) {
    $OutputDir = [Environment]::GetFolderPath("Desktop")
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    throw "Output directory not found: $OutputDir"
}

$tmpDir = Join-Path $env:TEMP "opencode"
if (-not (Test-Path -LiteralPath $tmpDir)) {
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
}

$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$responsePath = Join-Path $tmpDir ("image_gen_response_" + $timestamp + ".json")

$hasRefs = ($ReferenceImages -and $ReferenceImages.Count -gt 0)

function Download-Result {
    param($resultData)
    $savedFiles = @()
    $resultData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $responsePath

    if (-not $resultData.urls -or $resultData.urls.Count -lt 1) {
        throw "Task completed but no image URLs found"
    }

    for ($i = 0; $i -lt $resultData.urls.Count; $i++) {
        $url = $resultData.urls[$i]
        if ($FileName) {
            if ($resultData.urls.Count -eq 1) {
                $name = $FileName
            }
            else {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
                $ext = [System.IO.Path]::GetExtension($FileName)
                if (-not $ext) { $ext = ".png" }
                $name = "$baseName-$($i + 1)$ext"
            }
        }
        else {
            $name = "generated_${timestamp}_$($i + 1).png"
        }
        if ([System.IO.Path]::GetExtension($name) -eq "") { $name += ".png" }
        $outputPath = Join-Path $OutputDir $name
        Write-Host "Downloading $url -> $outputPath"
        Invoke-WebRequest -Uri $url -OutFile $outputPath -TimeoutSec 300
        $savedFiles += $outputPath
    }
    return $savedFiles
}

# ----------------------------------------------------------------
#  SYNC MODE (original blocking endpoint)
# ----------------------------------------------------------------
if (-not $Async) {
    if (-not $hasRefs) {
        $body = @{
            model   = $Model
            prompt  = $Prompt
            size    = $Size
            n       = $Count
            quality = $Quality
        } | ConvertTo-Json -Depth 5

        $response = Invoke-RestMethod -Method Post `
            -Uri "$BaseUrl/images/generations" `
            -Headers @{ Authorization = "Bearer $ApiKey" } `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 300
    }
    else {
        $client = New-Object System.Net.Http.HttpClient
        $client.DefaultRequestHeaders.Authorization = `
            New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $ApiKey)
        $client.Timeout = [TimeSpan]::FromSeconds(300)

        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent($Prompt)), "prompt")
        $form.Add((New-Object System.Net.Http.StringContent($Model)), "model")
        $form.Add((New-Object System.Net.Http.StringContent($Size)), "size")
        $form.Add((New-Object System.Net.Http.StringContent($Count.ToString())), "n")
        $form.Add((New-Object System.Net.Http.StringContent($Quality)), "quality")

        foreach ($imgPath in $ReferenceImages) {
            if (Test-Path -LiteralPath $imgPath) {
                $fileStream = [System.IO.File]::OpenRead($imgPath)
                $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
                $fileName = Split-Path -Leaf $imgPath
                $form.Add($fileContent, "image", $fileName)
            }
            else {
                $imageBytes = $client.GetByteArrayAsync($imgPath).GetAwaiter().GetResult()
                $byteContent = New-Object System.Net.Http.ByteArrayContent($imageBytes)
                $byteContent.Headers.ContentType = `
                    [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
                $form.Add($byteContent, "image", "ref_$([System.IO.Path]::GetFileName($imgPath))")
            }
        }

        $responseMsg = $client.PostAsync("$BaseUrl/images/edits", $form).GetAwaiter().GetResult()
        $responseBody = $responseMsg.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        if (-not $responseMsg.IsSuccessStatusCode) {
            throw "API returned $($responseMsg.StatusCode): $responseBody"
        }

        $response = $responseBody | ConvertFrom-Json
        $client.Dispose()
    }

    $response | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $responsePath

    if (-not $response.data -or $response.data.Count -lt 1) {
        throw "Image API response did not contain any image data"
    }

    $savedFiles = @()
    for ($i = 0; $i -lt $response.data.Count; $i++) {
        $item = $response.data[$i]

        if ($FileName) {
            if ($response.data.Count -eq 1) {
                $name = $FileName
            }
            else {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
                $ext = [System.IO.Path]::GetExtension($FileName)
                if (-not $ext) { $ext = ".png" }
                $name = "$baseName-$($i + 1)$ext"
            }
        }
        else {
            $name = "generated_${timestamp}_$($i + 1).png"
        }
        if ([System.IO.Path]::GetExtension($name) -eq "") { $name += ".png" }
        $outputPath = Join-Path $OutputDir $name

        if ($item.b64_json) {
            [System.IO.File]::WriteAllBytes($outputPath, [Convert]::FromBase64String($item.b64_json))
        }
        elseif ($item.url) {
            Invoke-WebRequest -Uri $item.url -OutFile $outputPath -TimeoutSec 300
        }
        else {
            throw "Image item $i contained neither b64_json nor url"
        }
        $savedFiles += $outputPath
    }
    return $savedFiles
}

# ----------------------------------------------------------------
#  ASYNC MODE (submit + poll)
# ----------------------------------------------------------------
Write-Host "[Async] Submitting task..."

if (-not $hasRefs) {
    $body = @{
        model   = $Model
        prompt  = $Prompt
        size    = $Size
        n       = $Count
        quality = $Quality
    } | ConvertTo-Json -Depth 5

    $submitResp = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/images/generations:submit" `
        -Headers @{ Authorization = "Bearer $ApiKey" } `
        -ContentType "application/json" `
        -Body $body `
        -TimeoutSec 60
}
else {
    $client = New-Object System.Net.Http.HttpClient
    $client.DefaultRequestHeaders.Authorization = `
        New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $ApiKey)
    $client.Timeout = [TimeSpan]::FromSeconds(300)

    $form = New-Object System.Net.Http.MultipartFormDataContent
    $form.Add((New-Object System.Net.Http.StringContent($Prompt)), "prompt")
    $form.Add((New-Object System.Net.Http.StringContent($Model)), "model")
    $form.Add((New-Object System.Net.Http.StringContent($Size)), "size")
    $form.Add((New-Object System.Net.Http.StringContent($Count.ToString())), "n")
    $form.Add((New-Object System.Net.Http.StringContent($Quality)), "quality")

    foreach ($imgPath in $ReferenceImages) {
        if (Test-Path -LiteralPath $imgPath) {
            $fileStream = [System.IO.File]::OpenRead($imgPath)
            $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
            $fileName = Split-Path -Leaf $imgPath
            $form.Add($fileContent, "image", $fileName)
        }
        else {
            $imageBytes = $client.GetByteArrayAsync($imgPath).GetAwaiter().GetResult()
            $byteContent = New-Object System.Net.Http.ByteArrayContent($imageBytes)
            $byteContent.Headers.ContentType = `
                [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
            $form.Add($byteContent, "image", "ref_$([System.IO.Path]::GetFileName($imgPath))")
        }
    }

    $submitMsg = $client.PostAsync("$BaseUrl/images/edits:submit", $form).GetAwaiter().GetResult()
    $submitBody = $submitMsg.Content.ReadAsStringAsync().GetAwaiter().GetResult()

    if (-not $submitMsg.IsSuccessStatusCode) {
        throw "Async submit failed: $($submitMsg.StatusCode) $submitBody"
    }

    $submitResp = $submitBody | ConvertFrom-Json
    $client.Dispose()
}

$taskId = $submitResp.task_id
if (-not $taskId) {
    throw "Submit response missing task_id: $($submitResp | ConvertTo-Json)"
}
Write-Host "[Async] Task submitted: $taskId"

# Poll until done
$headers = @{ Authorization = "Bearer $ApiKey" }
$pollUrl = "$BaseUrl/images/tasks/$taskId"
$maxWaitSeconds = 300
$elapsed = 0

while ($elapsed -lt $maxWaitSeconds) {
    Start-Sleep -Seconds 5
    $elapsed += 5
    try {
        $taskResp = Invoke-RestMethod -Method Get -Uri $pollUrl -Headers $headers -TimeoutSec 60
    }
    catch {
        Write-Host "[Async] Poll error: $($_.Exception.Message) (retrying...)"
        continue
    }

    $status = $taskResp.status
    $phase = $taskResp.phase
    $progress = $taskResp.progress
    Write-Host "[Async] Status: $status | Phase: $phase | Progress: ${progress}%"

    if ($status -eq "succeeded") {
        Write-Host "[Async] Task succeeded!"
        $saved = Download-Result $taskResp
        return $saved
    }
    elseif ($status -eq "failed" -or $status -eq "refunded") {
        throw "Task ${status}: $($taskResp.error)"
    }
    elseif ($status -eq "cancelled") {
        throw "Task was cancelled"
    }
}

throw "Task did not complete within ${maxWaitSeconds}s"
