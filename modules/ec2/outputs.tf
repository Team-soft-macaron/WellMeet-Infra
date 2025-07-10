# 출력 변수
output "instance_id" {
  description = "EC2 인스턴스 ID"
  value       = aws_instance.public.id
}

output "public_ip" {
  description = "EC2 인스턴스의 고정 Public IP (Elastic IP)"
  value       = aws_eip.public.public_ip
}

output "security_group_id" {
  description = "EC2 인스턴스의 보안 그룹 ID"
  value       = aws_security_group.public_ec2.id
}

output "nat_instance_eni_id" {
  description = "NAT 인스턴스의 ENI ID"
  value       = aws_instance.public.primary_network_interface_id
}
