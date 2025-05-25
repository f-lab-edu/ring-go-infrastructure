terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  private_key_path = var.private_key_path
  fingerprint      = var.fingerprint
  region           = "ap-chuncheon-1"
}

# Compartment 정보 (기본 루트 compartment 사용)
data "oci_identity_tenancy" "user_tenancy" {
  tenancy_id = var.tenancy_ocid
}

# 가용 영역 확인
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# VCN (Virtual Cloud Network) 생성
resource "oci_core_vcn" "main_vcn" {
  compartment_id = var.tenancy_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "ring-go-vcn"
  dns_label      = "ringgovcn"
}

# 인터넷 게이트웨이 생성
resource "oci_core_internet_gateway" "main_ig" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "ring-go-internet-gateway"
}

# 라우트 테이블 생성
resource "oci_core_route_table" "main_rt" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "ring-go-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main_ig.id
  }
}

# 서브넷 생성
resource "oci_core_subnet" "main_subnet" {
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.main_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "ring-go-subnet"
  dns_label         = "ringgosubnet"
  route_table_id    = oci_core_route_table.main_rt.id
  security_list_ids = [oci_core_security_list.main_sl.id]
}

# 보안 목록 (Security List) 생성
resource "oci_core_security_list" "main_sl" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "ring-go-security-list"

  # SSH 접속 허용 (포트 22)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # MySQL 접속 허용 (포트 3306)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 3306
      max = 3306
    }
  }

  # Redis 접속 허용 (포트 6379)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 6379
      max = 6379
    }
  }

  # 모든 아웃바운드 허용
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Ubuntu 이미지 찾기 (E2.1.Micro용)
data "oci_core_images" "ubuntu" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Database Server (MySQL + Redis only)
resource "oci_core_instance" "database_server" {
  compartment_id      = var.tenancy_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "ring-go-database-server"
  shape               = "VM.Standard.E2.1.Micro"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 1
  }

  source_details {
    source_id   = data.oci_core_images.ubuntu.images[0].id
    source_type = "image"
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.main_subnet.id
    display_name     = "database-vnic"
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file("D:/dev/oci_ringgo_public_key.pub")
    user_data = base64encode(templatefile("${path.module}/database_only.sh", {
      mysql_password = var.mysql_root_password
    }))
  }
}
