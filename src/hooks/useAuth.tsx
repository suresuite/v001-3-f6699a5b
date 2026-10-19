// @ts-nocheck — schema mismatch: this file targets a supply-chain schema not yet migrated into this project. Remove once tables/RPCs are created.
import { createContext, useContext, useEffect, useRef, useState, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { loginBrowserSession, clearMintedToken } from '@/lib/auth/sessionMint';
import { currentSessionSubject, currentMintedToken } from '@/lib/auth/sessionState';
import { roleChangeNotice, watchProfileFreshness } from '@/lib/auth/sessionRefresh';
import { toast } from 'sonner';

interface User {
  id: string;
  name: string;
  /** The parts of `name`, derived by the database and read-only to the user (D209). */
  first_name?: string | null;
  last_name?: string | null;
  email: string;
  role: string;
  organization: string;
  display_name?: string | null;
  /** A token of `AVATAR_COLORS`; the image upload is retired (D206). */
  avatar_color?: string | null;
  phone?: string | null;
  is_active?: boolean;
  force_password_change?: boolean;
  password_expires_at?: string | null;
  password_changed_at?: string | null;
  /** Computed on the database clock when the row was read (D206). */
  password_expired?: boolean;
  /** The policy, `password_max_age()`, in days (D206). */
  password_max_age_days?: number | null;
  /** D207 — the account's ORGANIZATION's plan, read through `get_my_profile`. */
  access_period?: string | null;
  access_valid_from?: string | null;
  access_valid_until?: string | null;
  /** The organization's period has ended FOR THIS ACCOUNT, on the database clock. */
  access_expired?: boolean;
  /** A super admin is not locked out by their organization's period. */
  access_exempt?: boolean;
  project_limit?: number | null;
  projects_used?: number | null;
  user_limit?: number | null;
  users_used?: number | null;
}

/**
 * The account row's fields as `get_my_profile` returns them. The user is NAMED: the
 * browser calls as `anon`, and the GUC `set_current_user_context` sets is LOCAL to its
 * own request, so a call that named nobody resolved nobody and raised
 * `not_authenticated` for everyone — which is how forced and expired password changes
 * went unenforced (PLAN.md §4 D206).
 */
async function readProfile(userId: string) {
  const { data, error } = await supabase.rpc('get_my_profile', { p_user_id: userId });
  if (error) return { profile: null, error };
  const p = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
  if (!p) return { profile: null, error: { message: 'no account row' } };
  return {
    profile: {
      email: p.email as string,
      name: p.name as string | null,
      first_name: p.first_name as string | null,
      last_name: p.last_name as string | null,
      role: p.role as string | null,
      organization: p.organization as string | null,
      display_name: p.display_name as string | null,
      avatar_color: p.avatar_color as string | null,
      phone: p.phone as string | null,
      is_active: p.is_active as boolean,
      force_password_change: p.force_password_change as boolean,
      password_expires_at: p.password_expires_at as string | null,
      password_changed_at: p.password_changed_at as string | null,
      password_expired: p.password_expired as boolean,
      password_max_age_days: p.password_max_age_days as number | null,
      access_period: p.access_period as string | null,
      access_valid_from: p.access_valid_from as string | null,
      access_valid_until: p.access_valid_until as string | null,
      access_expired: p.access_expired as boolean,
      access_exempt: p.access_exempt as boolean,
      project_limit: p.project_limit as number | null,
      projects_used: p.projects_used == null ? null : Number(p.projects_used),
      user_limit: p.user_limit as number | null,
      users_used: p.users_used == null ? null : Number(p.users_used),
    },
    error: null,
  };
}

interface AuthContextType {
  user: User | null;
  login: (email: string, password: string) => Promise<{ success: boolean; error?: string }>;
  logout: () => Promise<void>;
  refreshProfile: () => Promise<void>;
  loading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        const id = currentSessionSubject();
        if (!id) return;
        const { profile } = await readProfile(id);
        if (!active) return;
        if (!profile || profile.is_active !== true || profile.access_expired) { clearMintedToken(); return; }
        setUser({ id, ...profile });
      } finally { if (active) setLoading(false); }
    })();
    return () => { active = false; };
  }, []);

  const login = async (email: string, password: string) => {
    try {
      setLoading(true);
      console.log('[AUTH] Starting login process for:', email);
      
      const userId = await loginBrowserSession(email, password);
      if (!userId) return { success: false, error: 'Invalid credentials or session service unavailable. Please try again.' };
      const userObj: User = { id: userId, name: 'User', email, role: 'user', organization: '' };
      // The account row: deactivation, forced change and password expiry. FAIL CLOSED —
      // an unreadable row used to be skipped silently, which is exactly how none of the
      // three was ever enforced (D206).
      const { profile, error: profileError } = await readProfile(userId);
      if (!profile) {
        clearMintedToken();
        console.error('[AUTH] Account status could not be read:', profileError);
        return { success: false, error: 'Could not verify your account status. Please try again.' };
      }
      if (profile.is_active === false) {
        clearMintedToken();
        return { success: false, error: 'Your account has been deactivated. Contact your administrator.' };
      }
      if (profile.access_expired) {
        clearMintedToken();
        return { success: false, error: 'Your organization\'s access period has ended. Contact your administrator to renew it.' };
      }
      Object.assign(userObj, profile, {
        name: profile.name || userObj.name,
        role: profile.role || userObj.role,
        organization: profile.organization || userObj.organization,
      });

      setUser(userObj);
      localStorage.setItem('auth_user', JSON.stringify(userObj));
      console.log('[AUTH] User stored in localStorage');

      return { success: true };
    } catch (error) {
      console.error('[AUTH] Login error:', error);
      return { success: false, error: 'Login failed. Please try again.' };
    } finally {
      setLoading(false);
    }
  };

  const logout = async () => {
    console.log('[AUTH] Logging out user');
    clearMintedToken();
    await supabase.realtime.setAuth('');
    await supabase.removeAllChannels();
    setUser(null);
    localStorage.removeItem('auth_user');
  };

  const refreshProfile = async () => {
    if (!user?.id) return;
    const { profile, error } = await readProfile(user.id);
    if (!profile) {
      console.warn('[AUTH] Account status unavailable:', error);
      await logout();
      return;
    }
    // A session that outlived its account: suspended, or its organization's access
    // period ended since sign-in (D207). The database refuses the next sign-in either way.
    if (profile.is_active === false || profile.access_expired) {
      await logout();
      return;
    }
    const updated: User = {
      ...user,
      ...profile,
      name: profile.name || user.name,
      role: profile.role || user.role,
      organization: profile.organization || user.organization,
    };
    // D278 — a super admin changed the role while this tab was open. Said once: the next
    // refresh compares against the role stored here.
    const notice = roleChangeNotice(user.role, updated.role);
    if (notice) toast.info(notice);
    setUser(updated);
    localStorage.setItem('auth_user', JSON.stringify(updated));
  };
  // The listeners below outlive a render; they call the latest refreshProfile, not the
  // one closed over the user of the render that installed them.
  const refreshRef = useRef(refreshProfile);
  refreshRef.current = refreshProfile;

  useEffect(() => {
    // State initialized synchronously from localStorage
    console.log('[AUTH] AuthProvider mounted. User present:', !!user);
    
    if (user?.id && currentMintedToken()) refreshProfile();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once per signed-in user
  }, [user?.id, user?.email]);

  // D278 — an account changed elsewhere (a role on /admin/users) reaches an open tab: on
  // focus, on becoming visible, and every five minutes while signed in.
  useEffect(() => {
    if (!user?.id) return;
    const stop = watchProfileFreshness(() => { refreshRef.current(); });
    const timer = setInterval(() => { if (!currentMintedToken()) logout(); }, 1000);
    return () => { stop(); clearInterval(timer); };
  }, [user?.id]);

  return (
    <AuthContext.Provider value={{ user, login, logout, refreshProfile, loading }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};