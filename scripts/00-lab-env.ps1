$env:LAB_ROOT = "D:\daihoc\Nam4\Doan\lab"
$env:MINIKUBE_HOME = "$env:LAB_ROOT\_state\minikube"
$env:KUBECONFIG = "$env:LAB_ROOT\_state\kube\config"

$global:MINIKUBE_EXE = "$env:LAB_ROOT\tools\minikube\minikube.exe"

Write-Host "LAB_ROOT=$env:LAB_ROOT"
Write-Host "MINIKUBE_HOME=$env:MINIKUBE_HOME"
Write-Host "KUBECONFIG=$env:KUBECONFIG"
Write-Host "MINIKUBE_EXE=$global:MINIKUBE_EXE"
