def require_auth(f):
  def wrapper(*a, **k):
    return f(*a, **k)
  return wrapper
