#!/usr/bin/env python3
"""
Script to enable Claude Code proxy configuration.
Usage: claude_enable.py <master_key>
"""
import json
import sys
import os
from pathlib import Path

def main():
    if len(sys.argv) != 2:
        print("Usage: claude_enable.py <master_key>")
        sys.exit(1)

    master_key = sys.argv[1]
    claude_dir = Path.home() / '.claude'
    settings_file = claude_dir / 'settings.json'

    # Create .claude directory if it doesn't exist
    claude_dir.mkdir(exist_ok=True)

    # Load existing settings or create empty dict
    settings = {}
    if settings_file.exists():
        try:
            with open(settings_file, 'r') as f:
                settings = json.load(f)
        except (json.JSONDecodeError, IOError):
            settings = {}

    # Preserve any existing env entries; only overwrite proxy-related keys.
    env = settings.get('env', {}) or {}
    env.update({
        'ANTHROPIC_AUTH_TOKEN': master_key,
        'ANTHROPIC_BASE_URL': 'http://localhost:4444',
        'ANTHROPIC_MODEL': 'claude-opus-4-7',
        'ANTHROPIC_SMALL_FAST_MODEL': 'claude-haiku-4-5',
        # Copilot doesn't pass through Anthropic cache_control headers; omit
        # the attribution block so any LiteLLM-side cache keys on body match.
        'CLAUDE_CODE_ATTRIBUTION_HEADER': '0',
    })
    settings['env'] = env

    # Update model to use
    settings['model'] = 'claude-opus-4-7'

    # Add schema if it's a new file
    if '$schema' not in settings:
        settings['$schema'] = 'https://json.schemastore.org/claude-code-settings.json'

    # Save updated settings
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)

    print('✅ Updated settings while preserving existing configuration')

if __name__ == '__main__':
    main()