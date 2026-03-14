output "sg_elasticsearch_id" {
  value = aws_security_group.sg_elasticsearch.id
}

output "sg_kibana_id" {
  value = aws_security_group.sg_kibana.id
}

output "sg_logstash_id" {
  value = aws_security_group.sg_logstash.id
}
