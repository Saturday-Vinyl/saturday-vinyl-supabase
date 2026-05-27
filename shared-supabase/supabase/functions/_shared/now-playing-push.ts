// Shared payload builder for the `now_playing` push.
//
// Both `process-now-playing-event` (original send) and `retry-notification`
// (admin-triggered re-send) construct the same FCM payload via this builder,
// so retries are byte-identical to the original send and we don't drift if the
// album title format changes.

import type { SendFcmPushArgs } from './send-fcm-push.ts'

export interface AlbumInfo {
  library_album_id: string
  album_id?: string
  title: string
  artist: string
  cover_image_url?: string | null
  colors?: Record<string, unknown> | null
  library_id?: string
  library_name?: string
}

export function buildNowPlayingPushArgs(args: {
  tokenString: string
  albumInfo: AlbumInfo | null
  deviceName: string
}): SendFcmPushArgs {
  const { tokenString, albumInfo, deviceName } = args

  const title = albumInfo?.title
    ? `Now Playing: ${albumInfo.title}`
    : 'Record Detected'
  const body = albumInfo?.artist
    ? `${albumInfo.artist} on ${deviceName}`
    : `A record was placed on ${deviceName}`

  return {
    token: tokenString,
    title,
    body,
    data: {
      type: 'now_playing',
      library_album_id: albumInfo?.library_album_id || '',
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    android: { channel_id: 'now_playing', priority: 'high' },
    apns: { sound: 'default', badge: 1 },
  }
}
