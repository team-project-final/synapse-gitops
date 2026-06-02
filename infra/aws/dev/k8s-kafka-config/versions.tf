terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# bastion 내부 실행 전제: kubeconfig는 user_data에서 update-kubeconfig 완료(bastion.tf).
provider "kubernetes" {
  config_path = "~/.kube/config"
}
