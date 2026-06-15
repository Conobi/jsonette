"""On-Demand (lazy) JSON reader package.

Re-exports the owning `Reader`, the free `iter(...)` entry, and the M0 handle
types. Callers obtain the root handle from `iter(...).root()` by inference and
never name these `[o]`-parametric types.
"""

from jsonette.ondemand.reader import Reader, iter
from jsonette.ondemand.ondemand import Object, Value, Array, Field
