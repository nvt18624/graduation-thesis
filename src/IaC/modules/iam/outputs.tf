output "elasticsearch_instance_profile" {
  value = aws_iam_instance_profile.elasticsearch.name
}

output "kibana_instance_profile" {
  value = aws_iam_instance_profile.kibana.name
}

output "logstash_instance_profile" {
  value = aws_iam_instance_profile.logstash.name
}
