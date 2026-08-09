resource "aws_iam_user" "users" {

  for_each= {for user in local.users: "${user.first_name}-${user.last_name}" => user}
  name=lower("${substr(each.value.first_name,0,1)}${each.value.last_name}")

  path="/users/"

  tags={
    "DisplayName" ="${each.value.first_name} ${each.value.last_name}"
    "Department" =each.value.department
    "JobTitle" =each.value.job_title
  }

}

resource "aws_iam_user_login_profile" "users" {
  for_each = aws_iam_user.users
  user = each.value.name
  password_reset_required= true

  lifecycle {
    ignore_changes=[password_reset_required, password_length]
    
  }
}
