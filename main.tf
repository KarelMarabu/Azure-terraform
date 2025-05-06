# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
  subscription_id = "08011c03-25d3-44cf-8297-179e049cbb2d" # Zadejte své subscription ID
}

# Azure Active Directory provider
provider "azuread" {
  tenant_id = "f72c361c-f26b-4481-9722-c2a9024c3e01" # Zadejte své tenant ID
}

###############################
# Registrace app #
###############################

data "azuread_client_config" "current" {}

resource "azuread_application" "example" {
  display_name     = "example"
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMultipleOrgs"


  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182" # offline.access
      type = "Scope"
    }

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }
    resource_access {
      id   = "14dad69e-099b-42c9-810b-d002981feec1" # profile
      type = "Scope"
    }
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # user.read
      type = "Scope"
    }
  }

}

# neni asi třeba
# Vytvoření Service Principal pro aplikaci
resource "azuread_service_principal" "vpn_sp" {
  client_id = azuread_application.example.client_id
}

# Vytvoření Resource Group pro VPN
resource "azurerm_resource_group" "vpn" {
  name     = "T-VPN-ResourceGroup"
  location = "West Europe"
}

# Vytvoření Security Group pro VPN
resource "azurerm_network_security_group" "vpn_sg" {
  name                = "T-VPN"
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name
}

# Specifikace veřejné IP adresy pro VPN Gateway
resource "azurerm_public_ip" "vpn_gateway_ip" {
  name                = "T-VPN-Gateway-IP"
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [1]
}
# Vytvoření Virtual Network pro VPN Gateway (nutné pro subnety)
resource "azurerm_virtual_network" "vpn_network" {
  name                = "T-VPN-Network"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name
}

resource "azurerm_subnet" "gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.vpn.name
  virtual_network_name = azurerm_virtual_network.vpn_network.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Vytvoření VPN Gateway
resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = "T-VPN-Gateway"
  location            = azurerm_resource_group.vpn.location
  resource_group_name = azurerm_resource_group.vpn.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw2AZ"
  active_active       = false
  enable_bgp          = false

  ip_configuration {
    name                          = "vpngatewayconfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway_ip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id

  }


  vpn_client_configuration {
    address_space = ["172.16.0.0/24"]

    vpn_client_protocols = ["OpenVPN"]

    aad_tenant   = "https://login.microsoftonline.com/f72c361c-f26b-4481-9722-c2a9024c3e01/"
    aad_audience = azuread_application.example.client_id
    aad_issuer   = "https://sts.windows.net/f72c361c-f26b-4481-9722-c2a9024c3e01/"

  }
}