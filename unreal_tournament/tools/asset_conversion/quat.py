import math

# Quaternions as (x, y, z, w), and vectors as (x, y, z)


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def qconj(q):
    return (-q[0], -q[1], -q[2], q[3])


def rotate(q, v):
    """Turns the vector v by the quaternion q."""
    return qmul(qmul(q, (v[0], v[1], v[2], 0)), qconj(q))[:3]


def axis_angle(axis, angle):
    """The quaternion of a turn by angle (radians) about axis (a unit vector)."""
    s = math.sin(angle / 2)
    return (axis[0] * s, axis[1] * s, axis[2] * s, math.cos(angle / 2))
