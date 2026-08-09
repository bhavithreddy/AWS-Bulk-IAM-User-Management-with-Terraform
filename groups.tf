resource "aws_iam_group" "Engineering"{
    name ="Engineers"
    path="/groups/"

}

resource "aws_iam_group" "Sales"{
    name ="Sales"
    path="/groups/"

}

resource "aws_iam_group" "Marketing"{
    name ="Marketing"
    path="/groups/"

}

resource "aws_iam_group" "Finance"{
    name ="Finance"
    path="/groups/"

}

resource "aws_iam_group" "HR"{
    name ="HR"
    path="/groups/"

}

resource "aws_iam_group" "Operations"{
    name ="Operations"
    path="/groups/"

}



resource "aws_iam_group_membership" "Engineering"{
    name="Engineering-memebership"
    group=aws_iam_group.Engineering.name

    users=[
        for user in aws_iam_user.users : user.name if user.tags.Department=="Engineering"
    ]
}

resource "aws_iam_group_membership" "Sales"{
    name="Sales-memebership"
    group=aws_iam_group.Sales.name

    users=[
        for user in aws_iam_user.users : user.name if user.tags.Department=="Sales"
    ]
}

resource "aws_iam_group_membership" "Marketing"{
    name="Marketing-memebership"
    group=aws_iam_group.Marketing.name

    users=[
        for user in aws_iam_user.users : user.name if user.tags.Department=="Marketing"
    ]
}

resource "aws_iam_group_membership" "Finance"{
    name="Finance-memebership"
    group=aws_iam_group.Finance.name

    users=[
        for user in aws_iam_user.users : user.name if user.tags.Department=="Finance"
    ]
}

resource "aws_iam_group_membership" "HR"{
    name="HR-memebership"
    group=aws_iam_group.HR.name

    users=[
        for user in aws_iam_user.users : user.name if user.tags.Department=="HR"
    ]
}

resource "aws_iam_group_membership" "Operations"{
    name="Operations-memebership"
    group=aws_iam_group.Operations.name

    users=[
        for user in aws_iam_user.users : user.name if user.tags.Department=="Operations"
    ]
}

