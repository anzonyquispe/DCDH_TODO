"""
did_multiplegt_dyn
==================
Python implementation of the de Chaisemartin & D'Haultfoeuille (2024)
difference-in-differences estimator with dynamic effects.

Main entry point
----------------
>>> from did_multiplegt_dyn import did_multiplegt_dyn
>>> result = did_multiplegt_dyn(df, outcome="y", group="g", time="t",
...                             treatment="d", effects=5)
>>> print(result)
"""

from .main import did_multiplegt_dyn
from .reset import reset_groups
from .results import DIDResult

__all__ = ["did_multiplegt_dyn", "reset_groups", "DIDResult"]
__version__ = "0.1.0"
