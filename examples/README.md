# Maven Version Checker Examples

This directory contains example configuration files for the `check-maven-versions` script.

## Repository Mapping Files

### sample-repo-mappings.txt

Example configuration file showing common patterns for mapping Maven property names to GitHub repository names when they differ.

**Usage:**
```bash
check-maven-versions --org YourOrganization --config examples/sample-repo-mappings.txt pom.xml
```

## Configuration File Format

Repository mapping files use a simple `property-name=repository-name` format:

```
# Comments start with #
user-auth-service=user-authentication-srvc
api-client=api-client-library
data-utils=data-utilities
```

## Common Mapping Patterns

- **Service suffix differences**: `auth-service=auth-srvc`
- **Naming convention differences**: `file-storage=file_storage_utils`
- **Library vs service naming**: `json-utils=json-utilities-library`
- **Abbreviation differences**: `notification-lib=notification-library`

## Creating Your Own Mappings

1. Create a new `.txt` file with your mappings
2. Use the format: `maven-property-name=github-repository-name`
3. Add comments with `#` for documentation
4. Run the script with `--config your-file.txt`

## Without Configuration Files

If no config file is provided, the script uses the Maven property name directly as the repository name:

```bash
check-maven-versions --org YourOrganization pom.xml
```

This works when your Maven property names match your GitHub repository names exactly.