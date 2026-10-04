"""Produce synthetic XML for Tend's offline mock, never for deployment."""
import importlib.util
from pathlib import Path
import sys
spec=importlib.util.spec_from_file_location('fixture',Path(__file__).with_name('test-prepare.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.m.prepare(m.fixture(),sys.argv[1])
