"""
NETRA — Configuration Loader
Loads configs/default_config.yaml and provides easy access to parameters.
"""
import os
import yaml
from pathlib import Path


# Project root: two levels up from src/
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "configs" / "default_config.yaml"


def load_config(config_path=None):
    """Load YAML configuration file.
    
    Args:
        config_path: Path to config file. Defaults to configs/default_config.yaml
        
    Returns:
        dict: Parsed configuration dictionary
    """
    path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
    
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")
    
    with open(path, 'r') as f:
        config = yaml.safe_load(f)
    
    return config


# Singleton config instance — import this directly
_config = None

def get_config(config_path=None):
    """Get or load the singleton config instance."""
    global _config
    if _config is None or config_path is not None:
        _config = load_config(config_path)
    return _config
