#!/bin/bash
# Install Meshtastic Python CLI
# Reference: https://meshtastic.org/docs/software/python/cli/installation/?install-python-cli=linux

set -e

echo "=========================================="
echo "Install Meshtastic Python CLI"
echo "=========================================="


# Install pytap2 (use python3 -m pip so --break-system-packages is passed correctly)
echo ""
echo "Installing pytap2..."
python3 -m pip install --upgrade pytap2 --break-system-packages

# Install meshtastic CLI
echo ""
echo "Installing meshtastic CLI..."
python3 -m pip install --upgrade "meshtastic[cli]" --break-system-packages
echo "✓ Meshtastic CLI installed successfully"

# Ensure ~/.local/bin is in PATH for this session (pip installs executables here)
export PATH="$HOME/.local/bin:$PATH"

# Verify installation
echo ""
echo "Verifying installation..."
if command -v meshtastic &> /dev/null; then
    MESHTASTIC_VERSION=$(meshtastic --version 2>&1 | head -n 1)
    echo "✓ Meshtastic CLI is available: $MESHTASTIC_VERSION"
else
    echo "✗ Meshtastic CLI installation failed: 'meshtastic' command not found"
    echo ""
    echo "  Try adding to PATH and run again:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "  Or add to ~/.bashrc: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
    echo ""
    exit 1
fi

echo ""
echo "=========================================="
echo "Meshtastic Python CLI installation complete!"
echo "=========================================="
echo ""
echo "You can now test the connection with:"
echo "  meshtastic --info"
echo ""
echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./02-configure-telemetry.sh"
echo ""
