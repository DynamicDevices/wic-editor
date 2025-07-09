# Security Policy

## Supported Versions

We provide security updates for the following versions of WIC Editor:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security vulnerabilities seriously. Please report security vulnerabilities responsibly.

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please send an email to: security@dynamicdevices.co.uk

Include the following information:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fixes (if any)

### What to expect:
- **Acknowledgment**: We'll acknowledge your report within 48 hours
- **Initial Assessment**: We'll provide an initial assessment within 5 business days
- **Status Updates**: We'll keep you updated on our progress
- **Resolution**: We aim to resolve critical vulnerabilities within 30 days

### Responsible Disclosure:
- Please allow us time to investigate and fix the vulnerability before public disclosure
- We'll credit you in our security advisories (unless you prefer to remain anonymous)
- We may contact you for additional information or clarification

## Security Considerations

### Script Execution
- WIC Editor requires sudo privileges for mounting filesystems
- The script handles user input and file operations
- Always verify the source of WIC images before processing

### File Handling
- Be cautious with file paths and permissions
- Validate custom files before adding to images
- Use interactive mode when unsure about file overwrites

### Network Security
- WIC Editor doesn't make network connections
- Be careful when downloading WIC images from untrusted sources
- Verify checksums of downloaded images

## Security Best Practices

1. **Always backup original WIC images**
2. **Review file conflicts in interactive mode**
3. **Use force mode (-f) only when necessary**
4. **Validate custom files before deployment**
5. **Keep WIC Editor updated to the latest version**
6. **Run on secure, updated systems**

## Reporting Non-Security Issues

For non-security issues, please use our [GitHub Issues](https://github.com/DynamicDevices/wic-editor/issues) page.
7. Code of Conduct
Create CODE_OF_CONDUCT.
