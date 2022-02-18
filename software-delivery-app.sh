#!/usr/bin/env bash

# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Verify that the scripts are being run from Linux and not Mac
if [[ $OSTYPE != "linux-gnu" ]]; then
    echo "ERROR: This script and consecutive set up scripts have only been tested on Linux. Currently, only Linux (debian) is supported. Please run in Cloud Shell or in a VM running Linux".
    exit;
fi

export SCRIPT_DIR=$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null || echo "${PWD}/$(dirname $0)")
PROJECT_ID_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)

# Create a logs folder and file and send stdout and stderr to console and log file 
mkdir -p ${SCRIPT_DIR}/app
SCRIPT_DIR=${SCRIPT_DIR}/app
mkdir -p ${SCRIPT_DIR}/logs
if [ ! -f ${SCRIPT_DIR}/logs/vars.sh ]; then
    cp ${SCRIPT_DIR}/../vars.sh ${SCRIPT_DIR}/logs/vars.sh
else
    source ${SCRIPT_DIR}/logs/vars.sh
fi
export LOG_FILE=${SCRIPT_DIR}/logs/bootstrap-$(date +%s).log
touch ${LOG_FILE}
exec 2>&1
exec &> >(tee -i ${LOG_FILE})

#functions.sh helps make the script interactive
source ${SCRIPT_DIR}/../functions.sh

#For persisting state
touch ${HOME}/.sdp.bash
grep -q "vars.sh" ${HOME}/.sdp.bash || (echo -e "source ${SCRIPT_DIR}/logs/vars.sh" >> ${HOME}/.sdp.bash)
grep -q ".sdp.bash" ${HOME}/.bashrc || (echo "source ${HOME}/.gcp-workshop.bash" >> ${HOME}/.bashrc)

# Ensure Org ID is defined otherwise collect
while [ -z ${ORG_NAME} ]
    do
    read -p "$(echo -e "Please provide your Organization Name (your active account must be Org Admin): ")" ORG_NAME
    done

# Validate ORG_NAME exists
ORG_ID=$(gcloud organizations list \
  --filter="display_name=${ORG_NAME}" \
  --format="value(ID)")
[ ${ORG_ID} ] || { echo "Organization with that name does not exist or you do not have correct permissions in this org."; exit; }

# Validate active user is org admin
export ADMIN_USER=$(gcloud config get-value account)
gcloud organizations get-iam-policy ${ORG_ID} --format=json | \
jq '.bindings[] | select(.role=="roles/resourcemanager.organizationAdmin")' | grep ${ADMIN_USER}  &>/dev/null

[[ $? -eq 0 ]] || { echo "Active user is not an organization admin in $ORG_NAME"; exit; }

# Ensure Billing account is defined otherwise collect
while [ -z ${BILLING_ACCOUNT_ID} ]
    do
    read -p "$(echo -e "Please provide your Billing Account ID (your active account must be Billing Account Admin): ")" BILLING_ACCOUNT_ID
    done

# Check if FOLDER_NAME is needed. If not, enter just press enter
read -p "$(echo -e "Please provide Folder Name. If you created your multi-tenant platform in a folder, provide that folder name : ")" FOLDER_NAME

# Ensure infra setup project name is defined
while [ -z ${INFRA_SETUP_PROJECT} ]
    do
    read -p "$(echo -e "Please provide the ID of multi-tenant admin project: ")" INFRA_SETUP_PROJECT
    done

# Ensure app setup project name is defined
while [ -z ${APP_SETUP_PROJECT} ]
    do
    read -p "$(echo -e "Please provide the name for App project factory: ")" APP_SETUP_PROJECT
    done

# # Ensure infra setup repo name is defined
# while [ -z ${INFRA_SETUP_REPO} ]
#     do
#     read -p "$(echo -e "Please provide the name for Infra setup github repo: ")" INFRA_SETUP_REPO
#     done

# Ensure app setup repo name is defined
while [ -z ${APP_SETUP_REPO} ]
    do
    read -p "$(echo -e "Please provide the name for App factory repo: ")" APP_SETUP_REPO
    done

# Ensure github user is defined
while [ -z ${GITHUB_USER} ]
    do
    read -p "$(echo -e "Please provide your github user: ")" GITHUB_USER
    done

# Ensure github personal access token is defined
while [ -z ${TOKEN} ]
    do
    read -p "$(echo -e "Please provide your github personal access token: ")" TOKEN
    done

# Ensure github org is defined
while [ -z ${GITHUB_ORG} ]
    do
    read -p "$(echo -e "Please provide your github org: ")" GITHUB_ORG
    done

# Ensure IAM group name is defined
while [ -z ${IAM_GROUP} ]
    do
    read -p "$(echo -e "Please provide the DevOps IAM group name you created as part of multi-tenant platform setup: ")" IAM_GROUP
    done
    
# This will change based on where we keep the template repos    
TEMPLATE_ORG="cloudguy-dev"
TEMPLATE_APP_REPO="software-delivery-app-infra"
CUSTOM_SA="devops-sa-${PROJECT_ID_SUFFIX}"
GITHUB_SECRET_NAME="github-token-app"
TEAM_TRIGGER_NAME="add-team-files"
APP_TRIGGER_NAME="create-app"
PLAN_TRIGGER_NAME="tf-plan"
APPLY_TRIGGER_NAME="tf-apply"

# Validate active user is billing admin for billing account
gcloud beta billing accounts get-iam-policy ${BILLING_ACCOUNT_ID} --format=json | \
jq '.bindings[] | select(.role=="roles/billing.admin")' | grep $ADMIN_USER &>/dev/null

[[ $? -eq 0 ]] || { echo "Active user is not an billing account billing admin in $BILLING_ACCOUNT_ID"; exit; }

#INFRA_SETUP_PROJECT_ID=${INFRA_SETUP_PROJECT}-${PROJECT_ID_SUFFIX}
APP_SETUP_PROJECT_ID=${APP_SETUP_PROJECT}-${PROJECT_ID_SUFFIX}
APP_GOLANG_TEMPLATE="app-template-golang"
APP_JAVA_TEMPLATE="app-template-java"
APP_ENV_TMPLATE="env-template"
APP_TF_MODULES="terraform-modules"

# Verify that the folder exist if the FOLDER_NAME was not entered blank
if [[ -n ${FOLDER_NAME} ]]; then 
    title_no_wait "Verifying the folder ${FOLDER_NAME} exists..."
    print_and_execute "folder_flag=$(gcloud resource-manager folders list --organization ${ORG_ID} | grep ${FOLDER_NAME} | wc -l)"
    if [ ${folder_flag} -eq 0 ]; then
        error_no_wait "${FOLDER_NAME} does not exist"
        exit 1
    else 
        FOLDER_ID=$(gcloud resource-manager folders list --organization=${ORG_ID} --filter="display_name=${FOLDER_NAME}" --format="value(ID)")
    fi
fi

# Create app setup project
# TODO : Add state handling for FOLDER_NAME

# Create app setup project
if [[ -n ${FOLDER_NAME} ]]; then
    title_no_wait "Creating App setup project ${APP_SETUP_PROJECT_ID}..."
    print_and_execute "gcloud projects create ${APP_SETUP_PROJECT_ID} \
        --folder ${FOLDER_ID} \
        --name ${APP_SETUP_PROJECT_ID} \
        --set-as-default"
else
    title_no_wait "Creating App setup project ${APP_SETUP_PROJECT_ID}..."
    print_and_execute "gcloud projects create ${APP_SETUP_PROJECT_ID}  \
       --name ${APP_SETUP_PROJECT_ID} \
       --set-as-default"  
fi

title_no_wait "Linking billing account to the ${APP_SETUP_PROJECT_ID}..."
print_and_execute "gcloud beta billing projects link ${APP_SETUP_PROJECT_ID} \
--billing-account ${BILLING_ACCOUNT_ID}"

#echo ${SCRIPT_DIR}/vars.sh
#grep -q "export INFRA_SETUP_PROJECT_ID.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export INFRA_SETUP_PROJECT_ID=${INFRA_SETUP_PROJECT_ID}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export APP_SETUP_PROJECT_ID.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export APP_SETUP_PROJECT_ID=${APP_SETUP_PROJECT_ID}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export BILLING_ACCOUNT_ID=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export BILLING_ACCOUNT_ID=${BILLING_ACCOUNT_ID}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export ORG_NAME=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export ORG_NAME=${ORG_NAME}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export ORG_ID=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export ORG_ID=${ORG_ID}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export FOLDER_NAME=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export FOLDER_NAME=${FOLDER_NAME}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export FOLDER_ID=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export FOLDER_ID=${FOLDER_ID}" >> ${SCRIPT_DIR}/logs/vars.sh
#grep -q "export INFRA_SETUP_REPO=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export INFRA_SETUP_REPO=${INFRA_SETUP_REPO}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export APP_SETUP_REPO=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export APP_SETUP_REPO=${APP_SETUP_REPO}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export GITHUB_USER=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export GITHUB_USER=${GITHUB_USER}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export TOKEN=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export TOKEN=${TOKEN}" >> ${SCRIPT_DIR}/logs/vars.sh
grep -q "export GITHUB_ORG=.*" ${SCRIPT_DIR}/logs/vars.sh || echo -e "export GITHUB_ORG=${GITHUB_ORG}" >> ${SCRIPT_DIR}/logs/vars.sh

source ${SCRIPT_DIR}/../vars.sh
set -e

# Creating github repo in your org and commiting the code from template to it
title_no_wait "Creating app setup repo ${APP_SETUP_REPO} in ${GITHUB_ORG}..."
print_and_execute "repo_id=$(curl -s -H "Authorization: token ${TOKEN}" -H "Accept: application/json" \
    -d "{ \
        \"name\": \"${APP_SETUP_REPO}\", \
        \"private\": true \
      }" \
   -X POST https://api.github.com/orgs/${GITHUB_ORG}/repos | jq '.id')"


title_no_wait "Cloning ${TEMPLATE_APP_REPO} from ${TEMPLATE_ORG} locally..."
print_and_execute "git clone  https://${GITHUB_USER}:${TOKEN}@github.com/${TEMPLATE_ORG}/${TEMPLATE_APP_REPO}  ${SCRIPT_DIR}/../${TEMPLATE_APP_REPO}"
print_and_execute "cd ${SCRIPT_DIR}/../${TEMPLATE_APP_REPO}"
title_no_wait "Adding remote to https://api.github.com/orgs/${GITHUB_ORG}/${APP_SETUP_REPO}..."
print_and_execute "git remote add ${APP_SETUP_REPO} https://${GITHUB_USER}:${TOKEN}@github.com/${GITHUB_ORG}/${APP_SETUP_REPO}" 
print_and_execute "git remote set-url origin https://${GITHUB_USER}:${TOKEN}@github.com/${GITHUB_ORG}/${APP_SETUP_REPO}" 
print_and_execute "git push origin"
title_no_wait "Replacing ${TEMPLATE_APP_REPO} with ${APP_SETUP_REPO} in the repo code..."
print_and_execute "find . -type f -exec sed -i "s/${TEMPLATE_APP_REPO}/${APP_SETUP_REPO}/g" {} +"
git config --global user.name ${GITHUB_USER}
git config --global user.email "${GITHUB_USER}github.com"
git add .
git commit -m "Replacing ${TEMPLATE_APP_REPO} with ${APP_SETUP_REPO}"
git push origin
print_and_execute "cd ${SCRIPT_DIR}/.."


title_no_wait "Creating other templates..."
for REPO in ${APP_GOLANG_TEMPLATE} ${APP_JAVA_TEMPLATE} ${APP_ENV_TMPLATE} ${APP_TF_MODULES}
do
    title_no_wait "Creating ${REPO} in ${GITHUB_ORG}..."
    print_and_execute "repo_id=$(curl -s -H "Authorization: token ${TOKEN}" -H "Accept: application/json" \
        -d "{ \
            \"name\": \"${REPO}\", \
            \"private\": true, \
            \"is_template\" : true \
        }" \
    -X POST https://api.github.com/orgs/${GITHUB_ORG}/repos | jq '.id')"
    title_no_wait "Cloning ${REPO} from ${TEMPLATE_ORG} locally..."
    print_and_execute "git clone  https://${GITHUB_USER}:${TOKEN}@github.com/${TEMPLATE_ORG}/${REPO}  ${SCRIPT_DIR}/../${REPO}"
    print_and_execute "cd ${SCRIPT_DIR}/../${REPO}"
    title_no_wait "Adding remote to https://api.github.com/orgs/${GITHUB_ORG}/${REPO}..."
    print_and_execute "git remote add ${REPO} https://${GITHUB_USER}:${TOKEN}@github.com/${GITHUB_ORG}/${REPO}" 
    print_and_execute "git remote set-url origin https://${GITHUB_USER}:${TOKEN}@github.com/${GITHUB_ORG}/${REPO}" 
    print_and_execute "git push origin"
    cd ${SCRIPT_DIR}/../
done

title_no_wait "Setting up App infra project..."
print_and_execute "gcloud config set project ${APP_SETUP_PROJECT_ID}"
print_and_execute "gcloud services enable cloudresourcemanager.googleapis.com \
cloudbilling.googleapis.com \
cloudbuild.googleapis.com \
iam.googleapis.com \
secretmanager.googleapis.com \
container.googleapis.com \
cloudidentity.googleapis.com"

title_no_wait "Getting project number for ${APP_SETUP_PROJECT}"
print_and_execute "APP_PROJECT_NUMBER=$(gcloud projects describe ${APP_SETUP_PROJECT_ID} --format=json | jq '.projectNumber')"

title_no_wait "Give secret manager admin access to Cloud Build account"
print_and_execute "gcloud projects add-iam-policy-binding ${APP_SETUP_PROJECT_ID} --member=serviceAccount:${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --role=roles/secretmanager.admin"
title_no_wait "Give iam security admin access to Cloud Build account"
print_and_execute "gcloud projects add-iam-policy-binding ${APP_SETUP_PROJECT_ID} --member=serviceAccount:${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --role=roles/iam.securityAdmin"
title_no_wait "Give service usage consumer access to Cloud Build account"
print_and_execute "gcloud projects add-iam-policy-binding ${APP_SETUP_PROJECT_ID} --member=serviceAccount:${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --role=roles/serviceusage.serviceUsageConsumer"

title_no_wait "Add Cloud build service account to the IAM group"
print_and_execute "gcloud identity groups  memberships add --group-email="${IAM_GROUP}@${ORG_NAME}" --member-email=${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
print_and_execute "gcloud identity groups  memberships modify-membership-roles --group-email="${IAM_GROUP}@${ORG_NAME}" --member-email=${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --add-roles=OWNER"

title_no_wait "Create a custom service account"
print_and_execute "gcloud iam service-accounts create ${CUSTOM_SA}"
title_no_wait "Allow customer service account to be impersonated by Cloud Build SA"
gcloud iam service-accounts add-iam-policy-binding \
    ${CUSTOM_SA}@${APP_SETUP_PROJECT_ID}.iam.gserviceaccount.com \
 --member="serviceAccount:${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/iam.serviceAccountTokenCreator"

title_no_wait "Add custom service account to the IAM group"
print_and_execute "gcloud identity groups  memberships add --group-email="${IAM_GROUP}@${ORG_NAME}" --member-email=${CUSTOM_SA}@${APP_SETUP_PROJECT_ID}.iam.gserviceaccount.com"
print_and_execute "gcloud identity groups  memberships modify-membership-roles --group-email="${IAM_GROUP}@${ORG_NAME}" --member-email=${CUSTOM_SA}@${APP_SETUP_PROJECT_ID}.iam.gserviceaccount.com --add-roles=MANAGER"

title_no_wait "Add Cloud build service account as billing account user on the org"
print_and_execute "gcloud organizations add-iam-policy-binding ${ORG_ID}  --member=serviceAccount:${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --role=roles/billing.user --condition=None"

title_no_wait "Give cloudbuild service account projectCreator role at Org level..."
print_and_execute "gcloud organizations add-iam-policy-binding ${ORG_ID}  --member=serviceAccount:${APP_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --role=roles/resourcemanager.projectCreator --condition=None"

title_no_wait "Adding github token to secret manager..."
print_and_execute "printf ${TOKEN} | gcloud secrets create ${GITHUB_SECRET_NAME} --data-file=-"

APP_TF_BUCKET="${APP_SETUP_PROJECT_ID}-infra-tf"

title_no_wait "Creating GCS bucket for holding terraform state files..."
print_and_execute "gsutil mb gs://${APP_TF_BUCKET}"

#cd ${APP_SETUP_REPO}
cd ${SCRIPT_DIR}/../
title_no_wait "Cloning https://github.com/${GITHUB_ORG}/${APP_SETUP_REPO}"
print_and_execute "git clone  https://${GITHUB_USER}:${TOKEN}@github.com/${GITHUB_ORG}/${APP_SETUP_REPO}"
cd ${APP_SETUP_REPO}
title_no_wait "Replacing tf bucket in backend.tf in ${APP_SETUP_REPO}..."
sed -i "s/YOUR_APP_INFRA_TERRAFORM_STATE_BUCKET/${APP_TF_BUCKET}/" backend.tf
title_no_wait "Replacing github org in github.tf in ${APP_SETUP_REPO}..."
sed -i "s/YOUR_GITHUB_ORG/${GITHUB_ORG}/" github.tf
git config --global user.name ${GITHUB_USER}
git config --global user.email "${GITHUB_USER}github.com"
git add backend.tf github.tf
git commit -m "Replacing github org and GCS bucket"
git push origin



title_and_wait "ATTENTION : We need to connect Cloud Build in ${APP_SETUP_PROJECT_ID} with your github repo. As of now, there is no way of doing it automatically, press ENTER for instructions for doing it manually."
title_and_wait_step "Go to https://console.cloud.google.com/cloud-build/triggers/connect?project=${APP_SETUP_PROJECT_ID} \
Select \"Source\" as github and press continue. \
If it asks for authentication, enter your github credentials. \
Under \"Select Repository\" , on \"github account\" drop down click on \"+Add\" and choose ${GITHUB_ORG}. \
Click on \"repository\" drop down and select ${APP_SETUP_REPO}. \
Click the checkbox to agree to the terms and conditions and click connect. \
Click Done. \
"

title_no_wait "Creating Cloud Build trigger to add ad terraform files to create github team..."
print_and_execute "gcloud beta builds triggers create github --name=\"${TEAM_TRIGGER_NAME}\"  --repo-owner=\"${GITHUB_ORG}\" --repo-name=\"${APP_SETUP_REPO}\" --branch-pattern=\".*\" --build-config=\"add-team-tf-files.yaml\" \
--substitutions \"_GITHUB_SECRET_NAME\"=\"${GITHUB_SECRET_NAME}\",\"_GITHUB_ORG\"=\"${GITHUB_ORG}\",\"_GITHUB_USER\"=\"${GITHUB_USER}\",\"_TEAM_NAME\"=\"\" "

print_and_execute "ID1=$(gcloud beta builds triggers describe ${TEAM_TRIGGER_NAME} --format=json | jq '.id')"

title_no_wait "Creating Cloud Build trigger to add terraform files to create appliction..."
print_and_execute "gcloud beta builds triggers create github --name=\"${APP_TRIGGER_NAME}\"  --repo-owner=\"${GITHUB_ORG}\" --repo-name=\"${APP_SETUP_REPO}\"  --branch-pattern=\".*\" --build-config=\"add-app-tf-files.yaml\" \
--substitutions \"_APP_NAME\"=\"\",\"_APP_RUNTIME\"=\"\",\"_FOLDER_ID\"=\"\",\"_GITHUB_ORG\"=\"${GITHUB_ORG}\",\"_GITHUB_USER\"=\"${GITHUB_USER}\",\"_INFRA_PROJECT_ID\"=\"${INFRA_SETUP_PROJECT}\",\
\"_SA_TO_IMPERSONATE\"=\"${CUSTOM_SA}@${APP_SETUP_PROJECT_ID}.iam.gserviceaccount.com\",\"_GITHUB_SECRET_NAME\"=\"${GITHUB_SECRET_NAME}\" "

print_and_execute "ID2=$(gcloud beta builds triggers describe ${APP_TRIGGER_NAME} --format=json | jq '.id')"

title_no_wait "Creating Cloud Build trigger for tf-plan..."
print_and_execute "gcloud beta builds triggers create github --name=\"${PLAN_TRIGGER_NAME}\"   --repo-owner=\"${GITHUB_ORG}\"  --repo-name=\"${APP_SETUP_REPO}\" --branch-pattern=\".*\" --build-config=\"tf-plan.yaml\" \
--substitutions \"_GITHUB_SECRET_NAME\"=\"${GITHUB_SECRET_NAME}\",\"_GITHUB_USER\"=\"${GITHUB_USER}\" "

print_and_execute "ID3=$(gcloud beta builds triggers describe ${PLAN_TRIGGER_NAME} --format=json | jq '.id')"

title_no_wait "Creating Cloud Build trigger for tf-apply..."
print_and_execute "gcloud beta builds triggers create github --name=\"${APPLY_TRIGGER_NAME}\"   --repo-owner=\"${GITHUB_ORG}\"  --repo-name=\"${APP_SETUP_REPO}\" --branch-pattern=\".*\" --build-config=\"tf-apply.yaml\" \
--substitutions \"_GITHUB_SECRET_NAME\"=\"${GITHUB_SECRET_NAME}\",\"_GITHUB_USER\"=\"${GITHUB_USER}\" "

print_and_execute "ID4=$(gcloud beta builds triggers describe ${APPLY_TRIGGER_NAME} --format=json | jq '.id')"

title_and_wait "ATTENTION : As of Feb 2022, we can not create manual trigger via gcloud so we created a push triger above and now we need to manually change it to manual from the UI. Press ENTER for instructions for doing it manually."
title_and_wait_step "Go to https://console.cloud.google.com/cloud-build/triggers/edit/${ID1}?project=${APP_SETUP_PROJECT_ID} .Under "Event" , click "Manual Invocation". Change Branch name from master to main. Click Save."
title_and_wait_step "Go to https://console.cloud.google.com/cloud-build/triggers/edit/${ID2}?project=${APP_SETUP_PROJECT_ID} .Under "Event" , click "Manual Invocation". Change Branch name from master to main. Click Save."
title_and_wait_step "Go to https://console.cloud.google.com/cloud-build/triggers/edit/${ID3}?project=${APP_SETUP_PROJECT_ID} .Under "Event" , click "Manual Invocation". Change Branch name from master to main. Click Save."
title_and_wait_step "Go to https://console.cloud.google.com/cloud-build/triggers/edit/${ID4}?project=${APP_SETUP_PROJECT_ID} .Under "Event" , click "Manual Invocation". Change Branch name from master to main. Click Save."
