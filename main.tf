# 1. Конфигурация провайдера
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = ">= 0.47.0"
    }
  }
}

provider "yandex" {
  service_account_key_file = "key.json"  # Укажите путь к вашему ключу
  cloud_id  = "ваш_cloud_id"            # Замените на ваш cloud_id
  folder_id = "ваш_folder_id"           # Замените на ваш folder_id
  zone      = "ru-central1-a"
}

# 2. Создание сети и подсети
resource "yandex_vpc_network" "app-network" {
  name = "app-network"
}

resource "yandex_vpc_subnet" "app-subnet" {
  name           = "app-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.app-network.id
  v4_cidr_blocks = ["10.10.0.0/24"]
}

# 3. Создание двух виртуальных машин с Nginx (через count)
resource "yandex_compute_instance" "web-server" {
  count = 2
  name  = "web-server-${count.index + 1}"
  zone  = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8f6b7d6a2c7f3e8f1a"  # Ubuntu 22.04 LTS
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.app-subnet.id
    nat       = true
  }

  metadata = {
    user-data = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - nginx
    runcmd:
      - systemctl enable nginx
      - systemctl start nginx
    EOF
  }
}

# 4. Создание целевой группы
resource "yandex_lb_target_group" "app-target-group" {
  name = "app-target-group"

  dynamic "target" {
    for_each = yandex_compute_instance.web-server.*
    content {
      subnet_id = yandex_vpc_subnet.app-subnet.id
      address   = target.value.network_interface.0.ip_address
    }
  }
}

# 5. Создание сетевого балансировщика
resource "yandex_lb_network_load_balancer" "app-load-balancer" {
  name = "app-load-balancer"
  type = "external"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.app-target-group.id

    healthcheck {
      name = "http-healthcheck"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

# 6. Вывод информации
output "load_balancer_external_ip" {
  value = yandex_lb_network_load_balancer.app-load-balancer.listener.0.external_address_spec.0.address
  description = "Внешний IP адрес балансировщика"
}

output "vm_external_ips" {
  value = yandex_compute_instance.web-server.*.network_interface.0.nat_ip_address
  description = "Внешние IP адреса ВМ"
}

output "vm_internal_ips" {
  value = yandex_compute_instance.web-server.*.network_interface.0.ip_address
  description = "Внутренние IP адреса ВМ"
}