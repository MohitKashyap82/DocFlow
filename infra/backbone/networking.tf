# The account's default VPC's main route table has a dangling 0.0.0.0/0
# route pointing at an Internet Gateway that no longer exists (deleted in some
# earlier, unrelated experiment without cleaning up the route). That leaves
# the default VPC with no working internet path at all, which blocks the
# compute stack's internet-facing ALB. Fixed here (not in compute) so it's a
# one-time repair, not something torn down on every compute "down".

data "aws_vpc" "default" {
  default = true
}

data "aws_route_table" "main" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

resource "aws_internet_gateway" "default_vpc" {
  vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "complyflow-default-vpc-igw"
  }
}

resource "aws_route" "default_vpc_internet" {
  route_table_id         = data.aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default_vpc.id
}
