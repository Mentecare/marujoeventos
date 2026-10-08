"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { supabase } from "@/lib/supabase-browser";
import { EMPTY_PHOTOS, PHOTO_ACCEPT, PHOTO_MAX_BYTES, PORTFOLIO_LIMIT, type ProfilePhoto, type ProfilePhotoCollection } from "@/lib/profile-photos";

export async function requestProfilePhotos(query = "", init: RequestInit = {}) {
  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session) throw new Error("Entre na sua conta para acessar as fotos.");
  const response = await fetch(`/api/profile/photos${query}`, { ...init, cache: "no-store", headers: { ...init.headers, Authorization: `Bearer ${data.session.access_token}` } });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || "Não foi possível acessar as fotos. Tente novamente.");
  return result;
}

export function ProfileAvatar({ url, name, large = false }: { url?: string | null; name: string | null; large?: boolean }) {
  const [failed, setFailed] = useState<string | null>(null);
  const initials = (name || "EC").trim().split(/\s+/).slice(0, 2).map(part => part[0]).join("").toUpperCase();
  return <span className={`avatar${large ? " profileAvatarLarge" : ""}`}>
    {url && failed !== url ? <img src={url} alt={`Foto de ${name || "perfil"}`} onError={() => setFailed(url)}/> : initials}
  </span>;
}

function PhotoFigure({ photo, onRemove, busy }: { photo: ProfilePhoto; onRemove?: (id: string) => void; busy?: boolean }) {
  const [failed, setFailed] = useState(!photo.url);
  return <figure className="portfolioPhoto">
    {failed ? <p className="empty">Foto indisponível. Use Atualizar fotos para tentar novamente.</p> : <a href={photo.url} target="_blank" rel="noopener noreferrer" aria-label={photo.caption ? `Ampliar: ${photo.caption}` : "Ampliar foto de trabalho"}><img src={photo.url} alt={photo.caption || "Registro de trabalho enviado pelo profissional"} loading="lazy" onError={() => setFailed(true)}/></a>}
    {photo.caption && <figcaption>{photo.caption}</figcaption>}
    {onRemove && <button className="btn ghost" type="button" disabled={busy} onClick={() => onRemove(photo.id)} aria-label={`Remover foto${photo.caption ? `: ${photo.caption}` : " do portfólio"}`}>Remover foto</button>}
  </figure>;
}

function PhotoGallery({ photos, onRemove, busy }: { photos: ProfilePhoto[]; onRemove?: (id: string) => void; busy?: boolean }) {
  return photos.length ? <div className="portfolioGrid">{photos.map(photo => <PhotoFigure key={photo.id + photo.url} photo={photo} onRemove={onRemove} busy={busy}/>)}</div> : <p className="empty">Nenhuma foto de trabalho adicionada.</p>;
}

export function ProfilePhotoEditor({ name, photos, loading, loadError, onRefresh }: {
  name: string | null; photos: ProfilePhotoCollection; loading: boolean; loadError: string; onRefresh: () => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const lock = useRef(false);

  async function upload(event: FormEvent<HTMLFormElement>, kind: "avatar" | "portfolio") {
    event.preventDefault();
    if (lock.current || loading) return;
    const form = event.currentTarget;
    const fields = new FormData(form);
    const photo = fields.get("photo");
    setError(""); setNotice("");
    if (!(photo instanceof File) || !photo.size) { setError("Selecione uma foto para enviar."); return; }
    if (photo.size > PHOTO_MAX_BYTES) { setError("Cada foto pode ter até 3 MB."); return; }
    if (!PHOTO_ACCEPT.split(",").includes(photo.type)) { setError("Selecione uma foto em JPEG, PNG ou WebP."); return; }
    if (fields.get("real_declaration") !== "on") { setError("Confirme que a foto é real e não foi gerada com IA."); return; }
    fields.set("kind", kind); fields.set("real_declaration", "true");
    lock.current = true; setBusy(true);
    try {
      await requestProfilePhotos("", { method: "POST", body: fields });
      form.reset();
      setNotice(kind === "avatar" ? "Foto de perfil atualizada." : "Foto adicionada ao portfólio.");
      await onRefresh();
    } catch (error) { setError(error instanceof Error ? error.message : "Não foi possível enviar a foto."); }
    finally { lock.current = false; setBusy(false); }
  }

  async function remove(id: string) {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(""); setNotice("");
    try {
      await requestProfilePhotos(`?photo_id=${encodeURIComponent(id)}`, { method: "DELETE" });
      setNotice("Foto removida do perfil.");
      await onRefresh();
    } catch (error) { setError(error instanceof Error ? error.message : "Não foi possível remover a foto."); }
    finally { lock.current = false; setBusy(false); }
  }

  const disabled = busy || loading || Boolean(loadError);
  return <section className="profileMedia" aria-label="Fotos do meu perfil">
    <div className="rowActions"><button className="btn secondary" type="button" disabled={busy || loading} onClick={() => { void onRefresh().catch(() => {}); }}>Atualizar fotos</button></div>
    {loading && <p className="subtle" role="status">Carregando suas fotos…</p>}
    {loadError && <div className="error" role="alert"><span>{loadError}</span><button className="btn ghost" type="button" disabled={busy || loading} onClick={() => { void onRefresh().catch(() => {}); }}>Tentar novamente</button></div>}
    {error && <p className="error" role="alert">{error}</p>}
    {notice && <p className="notice" role="status">{notice}</p>}
    <section id="profile-photo" className="profilePhotoSection" tabIndex={-1}>
      <h3>Foto de perfil</h3>
      <div className="profilePhotoPreview"><ProfileAvatar url={photos.avatar?.url} name={name} large/>{photos.avatar && <button className="btn ghost" type="button" disabled={disabled} onClick={() => remove(photos.avatar!.id)}>Remover foto de perfil</button>}</div>
      <form className="form" onSubmit={event => upload(event, "avatar")}>
        <fieldset className="photoUploadFields" disabled={disabled}>
          <label>Nova foto de perfil<input className="input" name="photo" type="file" accept={PHOTO_ACCEPT} required/></label>
          <p className="subtle">JPEG, PNG ou WebP. Até 3 MB por foto.</p>
          <label className="check photoDeclaration"><input type="checkbox" name="real_declaration" required/>Confirmo que esta foto é real, tenho autorização para usá-la e ela não foi gerada com IA.</label>
          <button className="btn" type="submit">{busy ? "Aguarde…" : photos.avatar ? "Atualizar foto de perfil" : "Salvar foto de perfil"}</button>
        </fieldset>
      </form>
    </section>
    <section id="profile-portfolio" className="profilePhotoSection" tabIndex={-1}>
      <div className="sectionHead"><h3>Meu portfólio</h3><span className="subtle">{photos.portfolio.length} de {PORTFOLIO_LIMIT} fotos</span></div>
      <p className="subtle">Mostre registros reais dos trabalhos que você realizou. Os contratantes poderão vê-los no seu perfil profissional.</p>
      <PhotoGallery photos={photos.portfolio} onRemove={remove} busy={disabled}/>
      {photos.portfolio.length < PORTFOLIO_LIMIT ? <form className="form portfolioUpload" onSubmit={event => upload(event, "portfolio")}>
        <fieldset className="photoUploadFields" disabled={disabled}>
          <label>Foto de trabalho<input className="input" name="photo" type="file" accept={PHOTO_ACCEPT} required/></label>
          <label>Legenda opcional<input className="input" name="caption" maxLength={160} placeholder="Ex.: montagem de palco no Riocentro"/></label>
          <p className="subtle">Até 10 fotos, com até 3 MB cada. JPEG, PNG ou WebP.</p>
          <label className="check photoDeclaration"><input type="checkbox" name="real_declaration" required/>Confirmo que é um registro real de um trabalho que realizei, tenho autorização para publicá-lo e a foto não foi gerada com IA.</label>
          <button className="btn" type="submit">{busy ? "Aguarde…" : "Adicionar foto ao portfólio"}</button>
        </fieldset>
      </form> : <p className="notice">Você atingiu o limite de 10 fotos. Remova uma para adicionar outra.</p>}
      <p className="photoDisclosure subtle">A autenticidade é declarada por quem envia. Fotos geradas com IA não são permitidas.</p>
    </section>
  </section>;
}

export function ProfessionalPhotos({ freelancerId, organizationId, name }: { freelancerId?: string; organizationId?: string; name: string }) {
  const [photos, setPhotos] = useState<ProfilePhotoCollection>(EMPTY_PHOTOS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true); setError(""); setPhotos(EMPTY_PHOTOS);
    requestProfilePhotos(organizationId ? `?organization_id=${encodeURIComponent(organizationId)}` : `?freelancer_id=${encodeURIComponent(freelancerId||'')}`, { signal: controller.signal }).then(setPhotos).catch(error => {
      if (!controller.signal.aborted) setError(error instanceof Error ? error.message : "Não foi possível carregar o portfólio.");
    }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [freelancerId, organizationId, attempt]);
  return <section className="professionalPhotos" aria-label="Fotos do perfil profissional">
    {photos.avatar && <div className="profilePhotoPreview"><ProfileAvatar url={photos.avatar.url} name={name} large/></div>}
    <div className="sectionHead"><h3>Fotos de trabalhos</h3><button className="btn secondary" type="button" disabled={loading} onClick={() => setAttempt(value => value + 1)}>Atualizar fotos</button></div>
    {loading ? <p className="subtle" role="status">Carregando portfólio…</p> : error ? <div className="error" role="alert"><span>{error}</span><button className="btn ghost" onClick={() => setAttempt(value => value + 1)}>Tentar novamente</button></div> : <><PhotoGallery photos={photos.portfolio}/><p className="photoDisclosure subtle">Fotos enviadas pelo profissional, com declaração de registros reais dos próprios trabalhos e sem geração por IA.</p></>}
  </section>;
}
