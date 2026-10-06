#!/usr/bin/env python3
"""Compatibility entry point: dotfiles render."""
import sys
from dotfiles import main
sys.argv.insert(1, 'render')
raise SystemExit(main())
