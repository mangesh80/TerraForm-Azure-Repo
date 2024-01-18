# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "azureresgrp" {
  name = "mp-resources"

  location = "East Us"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "azurevmnw" {
  name                = "mp-virtual-network"
  resource_group_name = azurerm_resource_group.azureresgrp.name
  location            = azurerm_resource_group.azureresgrp.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }

}



resource "azurerm_subnet" "azureubnet" {
  name                 = "mp-subnet"
  resource_group_name  = azurerm_resource_group.azureresgrp.name
  virtual_network_name = azurerm_virtual_network.azurevmnw.name
  address_prefixes     = ["10.123.1.0/24"]


}

resource "azurerm_network_security_group" "azurenwsecgrp" {
  name                = "mp-nw-security-grp"
  location            = azurerm_resource_group.azureresgrp.location
  resource_group_name = azurerm_resource_group.azureresgrp.name

  security_rule {
    name                       = "mp-sec-rule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet_network_security_group_association" "mp-subnet-nw-sec-grp-assoc" {
  subnet_id                 = azurerm_subnet.azureubnet.id
  network_security_group_id = azurerm_network_security_group.azurenwsecgrp.id
}

resource "azurerm_public_ip" "azurerm-public-ip" {
  name                    = "mp-public-ip"
  location                = azurerm_resource_group.azureresgrp.location
  resource_group_name     = azurerm_resource_group.azureresgrp.name
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30

  tags = {
    environment = "dev"
  }
}


resource "azurerm_network_interface" "azurerm-nw-interface" {
  name                = "example-nic"
  location            = azurerm_resource_group.azureresgrp.location
  resource_group_name = azurerm_resource_group.azureresgrp.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.azureubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.azurerm-public-ip.id
  }
  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "azurerm-linux-virtual-machine" {
  name                  = "mp-virtual-machine"
  resource_group_name   = azurerm_resource_group.azureresgrp.name
  location              = azurerm_resource_group.azureresgrp.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.azurerm-nw-interface.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/mpid_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("linux-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/mpid_rsa"
    })
    interpreter = ["bash", "-c"]
  }
}

data "azurerm_public_ip" "azure-public-ip-data" {
  name                = azurerm_public_ip.azurerm-public-ip.name
  resource_group_name = azurerm_resource_group.azureresgrp.name

}

output "public_ip_address" {

  value = "${azurerm_linux_virtual_machine.azurerm-linux-virtual-machine.name}: ${data.azurerm_public_ip.azure-public-ip-data.ip_address}"
}