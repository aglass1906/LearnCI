# Supabase Email Code and Magic Link Setup

LearnCI requests passwordless email authentication with this callback:

```text
learnci://auth/callback
```

In the Supabase dashboard:

1. Add `learnci://auth/callback` to **Authentication > URL Configuration > Redirect URLs**.
2. Open **Authentication > Email Templates > Magic Link**.
3. Include both variables in the message:

```html
<p>Your LearnCI sign-in code is:</p>
<h2>{{ .Token }}</h2>

<p>Or sign in by tapping this link:</p>
<p><a href="{{ .ConfirmationURL }}">Sign in to LearnCI</a></p>
```

The code and link are two ways to complete the same Supabase authentication request. The iOS app handles the code with `verifyOTP` and the link through its `learnci` URL scheme.
