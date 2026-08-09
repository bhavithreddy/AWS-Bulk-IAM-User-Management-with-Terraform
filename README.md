# AWS Bulk IAM User Management with Terraform

> Bulk-provision AWS IAM users from a CSV file, dynamically assign them to groups based on department/job title, and enable secure console login — all fully automated with Terraform.

![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=flat&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonaws&logoColor=white)
![IAM](https://img.shields.io/badge/AWS%20IAM-DD344C?style=flat&logo=amazoniam&logoColor=white)
![Status](https://img.shields.io/badge/status-complete-brightgreen)

---

## 🎯 What This Project Does

Manually creating IAM users one at a time in the AWS Console doesn't scale — for an org onboarding dozens of employees, it's slow, inconsistent, and impossible to audit. This project solves that by treating **user identity data as code**: a single CSV file drives the entire provisioning pipeline, and Terraform turns that data into real, correctly-grouped, console-accessible IAM users.

**In one `terraform apply`, this project:**
1. Reads employee data (`first_name, last_name, department, job_title`) from a CSV file
2. Creates one IAM user per row, with a standardized username (`{first_initial}{lastname}`, e.g. `mscott`)
3. Enables AWS Console login for every user, forcing a password reset on first login
4. Creates department-based IAM groups (Education, Engineers, Managers)
5. Dynamically assigns each user to the correct group(s) based on their `department` and `job_title` tags — including a regex-based rule that pulls in anyone with "Manager" or "CEO" in their title, regardless of department

**Result:** 26 users → 58 AWS resources provisioned automatically, in seconds, from one CSV file.

---

## 🏗️ Architecture

```
                    ┌─────────────────┐
                    │   users.csv      │
                    │ first_name,      │
                    │ last_name,       │
                    │ department,      │
                    │ job_title        │
                    └────────┬─────────┘
                             │  csvdecode()
                             ▼
                    ┌─────────────────┐
                    │  local.users     │
                    │ (list of maps)   │
                    └────────┬─────────┘
                             │  for_each
                             ▼
              ┌──────────────────────────────┐
              │      aws_iam_user (x26)       │
              │  name = first_initial+lastname│
              │  tags = {Department,JobTitle} │
              └───────┬───────────────┬────────┘
                       │               │
                       ▼               │
        ┌───────────────────────┐      │
        │ aws_iam_user_login_   │      │
        │ profile (x26)         │      │
        │ console access +      │      │
        │ forced password reset │      │
        └───────────────────────┘      │
                                        │  for/if filter on tags
                     ┌──────────────────┼──────────────────┐
                     ▼                  ▼                  ▼
          ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
          │  Education      │  │  Engineers      │  │  Managers       │
          │  IAM Group      │  │  IAM Group      │  │  IAM Group      │
          │  (Department == │  │  (Department == │  │  (JobTitle       │
          │   "Education")  │  │   "Engineering")│  │   matches        │
          │                 │  │                 │  │   Manager|CEO)   │
          └────────────────┘  └────────────────┘  └────────────────┘

        State stored remotely in an S3 backend for team collaboration
        and safe concurrent access.
```

**Design principle at the center of this project:** tags aren't just metadata here — they're the *input* to a downstream decision (group membership). `DisplayName`, `Department`, and `JobTitle` get written onto each `aws_iam_user` resource specifically so that later `for`/`if` expressions can read them back and decide group placement. This is a pattern worth recognizing: **infrastructure state itself becomes the source of truth that drives further infrastructure logic**, instead of hardcoding group membership by hand.

---

## 🧰 Tech Stack

| Component | Purpose |
|---|---|
| Terraform | Infrastructure as Code — declarative, version-controlled user provisioning |
| AWS IAM | Users, login profiles, groups, group memberships |
| `csvdecode()` | Terraform built-in function that parses CSV into a list of maps |
| AWS S3 (backend) | Remote state storage for team collaboration and state locking |
| HCL functions | `lower()`, `substr()`, `contains()`, `can()`, `regex()` — used for dynamic naming and conditional group logic |

---

## 📁 Project Structure

```
iam-bulk-user-management/
├── backend.tf       # S3 remote backend configuration for Terraform state
├── provider.tf      # AWS provider configuration
├── versions.tf      # Terraform + provider version constraints
├── main.tf          # locals (csvdecode), aws_iam_user, aws_iam_user_login_profile
├── groups.tf         # aws_iam_group + aws_iam_group_membership resources
├── outputs.tf        # account_id, user_names, user_passwords (sensitive)
├── users.csv         # Source data — first_name, last_name, department, job_title
└── README.md
```

---

## ⚙️ How It Works — Key Terraform Concepts

### 1. Turning a CSV into usable Terraform data
```hcl
locals {
  users = csvdecode(file("users.csv"))
}
```
`csvdecode()` converts the raw CSV text into a list of maps — one map per row, keyed by column header. This is what makes the rest of the pipeline possible: everything downstream just iterates over `local.users`.

### 2. Bulk-creating users with `for_each`
```hcl
resource "aws_iam_user" "users" {
  for_each = { for user in local.users : "${user.first_name}-${user.last_name}" => user }

  name = lower("${substr(each.value.first_name, 0, 1)}${each.value.last_name}")
  path = "/users/"

  tags = {
    "DisplayName" = "${each.value.first_name} ${each.value.last_name}"
    "Department"  = each.value.department
    "JobTitle"    = each.value.job_title
  }
}
```
> **Note:** the key expression here uses `first_name-last_name` rather than `first_name` alone — using first name only breaks the moment two employees share a first name (`Duplicate object key` error), since `for_each` map keys must be unique.

### 3. Enabling console access safely
```hcl
resource "aws_iam_user_login_profile" "users" {
  for_each = aws_iam_user.users

  user                    = each.value.name
  password_reset_required = true

  lifecycle {
    ignore_changes = [password_reset_required, password_length]
  }
}
```
The `lifecycle { ignore_changes }` block matters here: without it, Terraform would try to "fix" the login profile back to its original state every time a user changes their own password after first login — which would be actively wrong behavior. This tells Terraform "manage this at creation, then hands off."

### 4. Dynamic group membership via `for`/`if`
```hcl
resource "aws_iam_group_membership" "education_members" {
  name  = "education-group-membership"
  group = aws_iam_group.education.name

  users = [
    for user in aws_iam_user.users : user.name
    if user.tags.Department == "Education"
  ]
}
```
No user is ever manually assigned to a group — membership is *derived* entirely from the tags set at creation time.

### 5. Regex-based manager detection (the advanced part)
```hcl
resource "aws_iam_group_membership" "managers_members" {
  name  = "managers-group-membership"
  group = aws_iam_group.managers.name

  users = [
    for user in aws_iam_user.users : user.name
    if contains(keys(user.tags), "JobTitle") && can(regex("Manager|CEO", user.tags.JobTitle))
  ]
}
```
`can(regex(...))` is doing double duty: `regex()` alone throws an error if there's no match, so wrapping it in `can()` converts "no match" into a clean `false` instead of crashing the whole plan. This means **any** job title containing "Manager" or "CEO" — "Regional Manager," "Assistant to the Regional Manager," "CEO" — gets swept into the Managers group without hardcoding every possible title string.

---

## 🚀 How to Run

```bash
# 1. Clone and enter the project
git clone <your-repo-url>
cd iam-bulk-user-management

# 2. Make sure users.csv is present with the correct headers:
#    first_name,last_name,department,job_title

# 3. Initialize (sets up the S3 backend)
terraform init

# 4. Review the plan — expect ~58 resources for 26 users
terraform plan

# 5. Apply
terraform apply
```

**Outputs after apply:**
```
account_id     = "716145636736"
user_names     = ["Michael Scott", "Dwight Schrute", "Jim Halpert", ...]
user_passwords = <sensitive>
```

**Always clean up demo/practice environments:**
```bash
terraform destroy
```

---

## 💼 Corporate / Business Perspective

This isn't a toy exercise — bulk, tag-driven IAM provisioning is a real pattern used in:
- **Employee onboarding automation** — HR systems (Workday, BambooHR) exporting new-hire data that feeds directly into access provisioning, instead of a manual IT ticket per person.
- **Least-privilege access at scale** — grouping users by role/department so permissions are attached to *groups*, not individuals, keeping access auditable and consistent as headcount grows.
- **Compliance and audit trails** — because everything is defined in Terraform and version-controlled, "who had access to what, and when" is answerable from Git history — something manual console-based IAM management can't offer.
- **Multi-hundred-employee orgs** — this exact `csvdecode()` + `for_each` + tag-driven grouping pattern is how platform/security teams handle onboarding at a scale where doing it by hand isn't an option.

**What this signals to a hiring manager:** you understand IAM isn't just "create a user" — it's identity lifecycle management (creation, access, grouping, least privilege) done in a way that's repeatable, auditable, and doesn't rely on a human remembering to do it correctly every time.

---

## 🎤 Interview Questions Based on This Project

**Q: Walk me through what `csvdecode()` actually returns.**
It parses CSV text into a list of maps, where each map represents one row and its keys come from the header line. This is what makes the CSV directly iterable in a `for_each` or `for` expression — no manual parsing needed.

**Q: Why did you key `for_each` on `first_name-last_name` instead of just `first_name`?**
Because `for_each` requires unique map keys — two employees sharing a first name would produce a "Duplicate object key" error otherwise. Even that isn't fully bulletproof at large scale (two people could share both names too), so a genuinely unique field like employee ID or email is the more robust long-term choice.

**Q: What does the `lifecycle { ignore_changes }` block do here, and why is it necessary?**
It tells Terraform to stop tracking drift on `password_reset_required`/`password_length` after initial creation. Without it, Terraform would try to revert a user's login profile back to its original state on every `apply` after the user changes their own password — which is both wrong behavior and would actually block real users from managing their own credentials.

**Q: Explain what `can(regex(...))` is doing and why not just use `regex()` alone.**
`regex()` throws a hard error when there's no match. Wrapping it in `can()` converts that error into `false`, letting you safely use it as a filter condition inside a `for/if` expression instead of crashing the entire `terraform plan` on the first user whose title doesn't match.

**Q: How would you extend this to also create IAM policies and attach them per group, not just group membership?**
Add `aws_iam_policy` resources per group (or reference AWS-managed policies), then `aws_iam_group_policy_attachment` resources keyed by group — following the same `for_each`-driven pattern already established for users and memberships.

**Q: What's a security concern with this design as written?**
Two worth naming: (1) `terraform apply` output includes `user_passwords` marked sensitive, but the initial passwords still need to reach each user through a secure channel — that hand-off process matters as much as generating them; (2) no MFA enforcement is configured here — production IAM setups should pair this with an MFA-required policy, not console login alone.

**Q: Why is state stored in S3 instead of locally?**
Local state doesn't support team collaboration — two people running `terraform apply` from local state risk conflicting, corrupting changes. An S3 backend (ideally with DynamoDB state locking) gives a single shared source of truth and prevents concurrent-apply race conditions.

---

## 🧾 Should You Put This on Your Resume?

**Yes — this is a legitimate, resume-worthy project**, but the value depends entirely on *how* you frame it. A couple of honest notes:

**Why it's worth including:**
- It demonstrates real Terraform fluency beyond basic resource creation: `for_each` over derived maps, `for`/`if` filtering, `csvdecode()`, `lifecycle` meta-arguments, and `regex()`/`can()` — these are genuinely intermediate-to-advanced HCL patterns, not copy-paste boilerplate.
- IAM/identity management is a core, constantly-tested DevOps/DevSecOps interview topic — this project gives you something concrete and specific to talk through rather than generic "I know IAM" claims.
- It shows you can think about infrastructure as a **data-driven system** (CSV in, correctly-grouped access out) — a mindset employers value more than "I clicked through Terraform tutorials."

**How to frame it well (this matters more than the project itself):**
- Don't just say "created IAM users with Terraform" — that undersells it. Emphasize the *dynamic, data-driven* nature and the specific HCL techniques.
- Suggested resume bullet:
  > "Automated bulk AWS IAM user provisioning and role-based access assignment using Terraform, dynamically grouping 26+ users via tag-driven `for`/`if` filtering and regex-based role detection — reducing manual onboarding effort and standardizing least-privilege access."
- Be ready to explain the `Duplicate object key` bug and how you fixed it (interviewers love hearing about a real bug you hit and diagnosed — it proves you actually built this, not copied it).

**What would make it noticeably stronger before you rely on it heavily in interviews:**
- Add IAM **policy attachment** per group (currently it only handles group *membership*, not actual permissions) — this is the natural, expected next step and its absence is the first thing a sharp interviewer will probe.
- Add MFA enforcement via an IAM policy condition — flagged above as a real gap.
- Consider replacing the CSV with a more realistic source (e.g., reading from an S3-hosted CSV, or accepting it as a Terraform variable) to show you've thought about how this integrates into a real onboarding pipeline, not just a local file.

**Bottom line:** include it, but pair it with at least one or two of the enhancements above if you can — "I built this and then identified and closed its security gaps" is a substantially stronger interview story than "I built this."

---

## ⚠️ Common Mistakes / Troubleshooting

| Symptom | Cause |
|---|---|
| `Error: Duplicate object key` on `terraform plan` | Two rows in `users.csv` produce the same `for_each` key (e.g., same first name) — key on a genuinely unique combination or field |
| Login profile keeps showing as "changed" on every plan | Missing `lifecycle { ignore_changes }` block — Terraform is trying to revert user-initiated password changes |
| User not appearing in expected group | Tag value mismatch — `for/if` filters do exact string comparison, so `"education"` won't match a filter checking for `"Education"` |
| `regex()` causing the whole plan to fail | Called directly instead of wrapped in `can()` — `regex()` throws when there's no match, `can()` catches that safely |
| CSV not found error | `users.csv` must be in the same directory Terraform is run from, and the path in `file("users.csv")` must match exactly |

---

## 🧹 Cleanup

```bash
terraform destroy
```
Don't leave 26+ demo IAM users sitting in your AWS account indefinitely — clean up once you've captured your screenshots/evidence for the portfolio.
