"""Opt-in Python socket guard for isolated tests and their subprocesses."""

import ipaddress
import socket

_connect = socket.socket.connect
_connect_ex = socket.socket.connect_ex
_getaddrinfo = socket.getaddrinfo


def _allowed(host):
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def _check(address):
    if isinstance(address, tuple) and not _allowed(address[0]):
        raise RuntimeError("TEST_EXTERNAL_NETWORK_BLOCKED")


def connect(self, address):
    _check(address)
    return _connect(self, address)


def connect_ex(self, address):
    _check(address)
    return _connect_ex(self, address)


def getaddrinfo(host, *args, **kwargs):
    if host is not None and not _allowed(host):
        raise RuntimeError("TEST_EXTERNAL_DNS_BLOCKED")
    return _getaddrinfo(host, *args, **kwargs)


socket.socket.connect = connect
socket.socket.connect_ex = connect_ex
socket.getaddrinfo = getaddrinfo
