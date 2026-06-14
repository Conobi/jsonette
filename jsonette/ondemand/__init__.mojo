"""On-Demand (lazy) JSON reader package.

Re-exports the M0 handle types. Callers obtain the root handle from
`Parser.iter(...)` by inference and never name these `[o]`-parametric types.
"""

from jsonette.ondemand.ondemand import ObjectHandle, ValueHandle
