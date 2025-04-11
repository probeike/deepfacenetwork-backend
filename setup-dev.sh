#!/bin/bash

# Initialize Terraform if not already initialized
if [ ! -d ".terraform" ]; then
  echo "Initializing Terraform..."
  terraform init
fi

# Select the default workspace (which will be treated as "dev")
echo "Selecting default workspace for local development..."
terraform workspace select default || echo "Already using default workspace"

echo "Your environment is now set up for local development (dev environment)"
echo "Run 'terraform plan' or 'terraform apply' to work with the dev environment"