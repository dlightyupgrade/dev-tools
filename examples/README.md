# Maven Version Checker Examples

This directory contains example configuration files for the `check-maven-versions` script.

## Repository Mapping Files

### credify-repo-mappings.txt

Configuration file for Credify/Upgrade organization repositories. Maps Maven property names to GitHub repository names when they differ.

**Usage:**
```bash
check-maven-versions --org Credify --config examples/credify-repo-mappings.txt pom.xml
```

## Configuration File Format

Repository mapping files use a simple `property-name=repository-name` format:

```
# Comments start with #
actor-bankruptcy=actor-bankruptcy-srvc
actor-srvc=actor-service
financial-utils=financial-utilities
```

## Creating Your Own Mappings

1. Create a new `.txt` file with your mappings
2. Use the format: `maven-property-name=github-repository-name`
3. Add comments with `#` for documentation
4. Run the script with `--config your-file.txt`

## Without Configuration Files

If no config file is provided, the script uses the Maven property name directly as the repository name:

```bash
check-maven-versions --org YourOrg pom.xml
```

This works when your Maven property names match your GitHub repository names exactly.