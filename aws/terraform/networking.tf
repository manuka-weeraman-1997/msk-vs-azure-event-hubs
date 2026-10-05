# Private-only network for MSK. No internet gateway or NAT is created; brokers
# are reachable only from inside the VPC (or peered/VPN networks you allow).

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.cluster_name}-vpc" }
}

# One private subnet per availability zone.
resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.cluster_name}-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.cluster_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group attached to producers and consumers running in this VPC.
resource "aws_security_group" "client" {
  name_prefix = "${var.cluster_name}-client-"
  description = "Attach to Kafka producers and consumers that need MSK access"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.cluster_name}-client-sg" }
}

# Security group for the brokers.
resource "aws_security_group" "msk" {
  name_prefix = "${var.cluster_name}-msk-"
  description = "MSK brokers: Kafka client ports from the client SG and optional CIDRs"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.cluster_name}-msk-sg" }
}

locals {
  # Kafka client ports:
  #   9098  TLS with SASL/IAM (always enabled in this configuration)
  #   9094  TLS with mutual TLS client certificates (only if enable_mutual_tls)
  #   9096  TLS with SASL/SCRAM (only if enable_sasl_scram)
  kafka_client_ports = concat(
    [9098],
    var.enable_mutual_tls ? [9094] : [],
    var.enable_sasl_scram ? [9096] : []
  )
}

# From the client security group.
resource "aws_vpc_security_group_ingress_rule" "from_client_sg" {
  for_each = toset([for p in local.kafka_client_ports : tostring(p)])

  security_group_id            = aws_security_group.msk.id
  referenced_security_group_id = aws_security_group.client.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  description                  = "Kafka client port ${each.value} from client SG"
}

# From optional extra CIDRs (empty by default).
resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = {
    for pair in setproduct(var.additional_client_cidrs, local.kafka_client_ports) :
    "${pair[0]}-${pair[1]}" => { cidr = pair[0], port = pair[1] }
  }

  security_group_id = aws_security_group.msk.id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = "Kafka client port ${each.value.port} from ${each.value.cidr}"
}

# Brokers talk to each other and to AWS services; allow outbound inside the VPC.
resource "aws_vpc_security_group_egress_rule" "msk_to_vpc" {
  security_group_id = aws_security_group.msk.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Broker traffic within the VPC"
}

# Clients may reach the brokers; extend this if clients also need other targets.
resource "aws_vpc_security_group_egress_rule" "client_to_msk" {
  for_each = toset([for p in local.kafka_client_ports : tostring(p)])

  security_group_id            = aws_security_group.client.id
  referenced_security_group_id = aws_security_group.msk.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  description                  = "Kafka client port ${each.value} to MSK"
}
