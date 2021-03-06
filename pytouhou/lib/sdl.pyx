# -*- encoding: utf-8 -*-
##
## Copyright (C) 2013 Emmanuel Gil Peyrot <linkmauve@linkmauve.fr>
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published
## by the Free Software Foundation; version 3 only.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##

import pytouhou.lib.gui as gui

from pytouhou.utils.helpers import get_logger

logger = get_logger(__name__)


GL_CONTEXT_MAJOR_VERSION = SDL_GL_CONTEXT_MAJOR_VERSION
GL_CONTEXT_MINOR_VERSION = SDL_GL_CONTEXT_MINOR_VERSION
GL_CONTEXT_PROFILE_MASK = SDL_GL_CONTEXT_PROFILE_MASK
GL_DOUBLEBUFFER = SDL_GL_DOUBLEBUFFER
GL_RED_SIZE = SDL_GL_RED_SIZE
GL_GREEN_SIZE = SDL_GL_GREEN_SIZE
GL_BLUE_SIZE = SDL_GL_BLUE_SIZE
GL_DEPTH_SIZE = SDL_GL_DEPTH_SIZE

GL_CONTEXT_PROFILE_CORE = SDL_GL_CONTEXT_PROFILE_CORE
GL_CONTEXT_PROFILE_COMPATIBILITY = SDL_GL_CONTEXT_PROFILE_COMPATIBILITY
GL_CONTEXT_PROFILE_ES = SDL_GL_CONTEXT_PROFILE_ES

WINDOWPOS_CENTERED = SDL_WINDOWPOS_CENTERED
WINDOW_OPENGL = SDL_WINDOW_OPENGL
WINDOW_RESIZABLE = SDL_WINDOW_RESIZABLE

SCANCODE_Z = SDL_SCANCODE_Z
SCANCODE_X = SDL_SCANCODE_X
SCANCODE_P = SDL_SCANCODE_P
SCANCODE_LSHIFT = SDL_SCANCODE_LSHIFT
SCANCODE_UP = SDL_SCANCODE_UP
SCANCODE_DOWN = SDL_SCANCODE_DOWN
SCANCODE_LEFT = SDL_SCANCODE_LEFT
SCANCODE_RIGHT = SDL_SCANCODE_RIGHT
SCANCODE_LCTRL = SDL_SCANCODE_LCTRL
SCANCODE_ESCAPE = SDL_SCANCODE_ESCAPE
SCANCODE_HOME = SDL_SCANCODE_HOME

WINDOWEVENT_RESIZED = SDL_WINDOWEVENT_RESIZED

KEYDOWN = SDL_KEYDOWN
QUIT = SDL_QUIT
WINDOWEVENT = SDL_WINDOWEVENT


class SDLError(gui.Error):
    def __init__(self):
        error = SDL_GetError()
        Exception.__init__(self, error.decode())


class SDL:
    def __init__(self, *, video=True, sound=True):
        self.sound = sound
        self.video = video

    def __enter__(self):
        global keyboard_state

        IF UNAME_SYSNAME == "Windows":
            SDL_SetMainReady()
        init(SDL_INIT_VIDEO if self.video else 0)
        img_init(IMG_INIT_PNG)
        ttf_init()

        keyboard_state = SDL_GetKeyboardState(NULL)

        if self.sound:
            mix_init(0)
            try:
                mix_open_audio(44100, MIX_DEFAULT_FORMAT, 2, 4096)
            except SDLError as error:
                logger.error(u'Impossible to set up audio subsystem: %s', error)
                self.sound = False
            else:
                # TODO: make it dependent on the number of sound files in the
                # archives.
                mix_allocate_channels(MAX_SOUNDS)

    def __exit__(self, *args):
        if self.sound:
            Mix_CloseAudio()
            Mix_Quit()

        TTF_Quit()
        IMG_Quit()
        SDL_Quit()


cdef class Window(gui.Window):
    def __init__(self, str title, int x, int y, int w, int h, Uint32 flags):
        title_bytes = title.encode()
        self.window = SDL_CreateWindow(title_bytes, x, y, w, h, flags)
        if self.window == NULL:
            raise SDLError()

    def __dealloc__(self):
        if self.context != NULL:
            SDL_GL_DeleteContext(self.context)
        if self.window != NULL:
            SDL_DestroyWindow(self.window)

    cdef void create_gl_context(self) except *:
        self.context = SDL_GL_CreateContext(self.window)
        if self.context == NULL:
            raise SDLError()

    cdef void present(self) nogil:
        if self.renderer == NULL:
            SDL_GL_SwapWindow(self.window)
        else:
            SDL_RenderPresent(self.renderer)

    cdef void set_window_size(self, int width, int height) nogil:
        SDL_SetWindowSize(self.window, width, height)

    cdef void set_swap_interval(self, int interval) except *:
        if SDL_GL_SetSwapInterval(interval) < 0:
            raise SDLError()

    cdef list get_events(self):
        cdef SDL_Event event
        ret = []
        while SDL_PollEvent(&event):
            if event.type == SDL_KEYDOWN:
                scancode = event.key.keysym.scancode
                if scancode == SDL_SCANCODE_ESCAPE:
                    ret.append((gui.PAUSE, None))
                elif scancode in (SDL_SCANCODE_P, SDL_SCANCODE_HOME):
                    ret.append((gui.SCREENSHOT, None))
                elif scancode == SDL_SCANCODE_DOWN:
                    ret.append((gui.DOWN, None))
                elif scancode == SDL_SCANCODE_F11:
                    ret.append((gui.FULLSCREEN, None))
                elif scancode == SDL_SCANCODE_RETURN:
                    mod = event.key.keysym.mod
                    if mod & KMOD_ALT:
                        ret.append((gui.FULLSCREEN, None))
            elif event.type == SDL_QUIT:
                ret.append((gui.EXIT, None))
            elif event.type == SDL_WINDOWEVENT:
                if event.window.event == SDL_WINDOWEVENT_RESIZED:
                    ret.append((gui.RESIZE, (event.window.data1, event.window.data2)))
        return ret

    cdef int get_keystate(self) nogil:
        cdef int keystate = 0
        cdef const Uint8 *keys = keyboard_state
        if keys[SCANCODE_Z]:
            keystate |= 1
        if keys[SCANCODE_X]:
            keystate |= 2
        if keys[SCANCODE_LSHIFT]:
            keystate |= 4
        if keys[SCANCODE_UP]:
            keystate |= 16
        if keys[SCANCODE_DOWN]:
            keystate |= 32
        if keys[SCANCODE_LEFT]:
            keystate |= 64
        if keys[SCANCODE_RIGHT]:
            keystate |= 128
        if keys[SCANCODE_LCTRL]:
            keystate |= 256
        return keystate

    cdef void toggle_fullscreen(self) nogil:
        ret = SDL_SetWindowFullscreen(self.window, 0 if self.is_fullscreen else SDL_WINDOW_FULLSCREEN_DESKTOP)
        if ret == -1:
            with gil:
                raise SDLError()
        self.is_fullscreen = not self.is_fullscreen

    # The following functions are there for the pure SDL backend.
    cdef bint create_renderer(self, Uint32 flags) except True:
        self.renderer = SDL_CreateRenderer(self.window, -1, flags)
        if self.renderer == NULL:
            raise SDLError()

    cdef bint render_clear(self) except True:
        ret = SDL_RenderClear(self.renderer)
        if ret == -1:
            raise SDLError()

    cdef bint render_copy(self, Texture texture, Rect srcrect, Rect dstrect) except True:
        ret = SDL_RenderCopy(self.renderer, texture.texture, &srcrect.rect, &dstrect.rect)
        if ret == -1:
            raise SDLError()

    cdef bint render_copy_ex(self, Texture texture, Rect srcrect, Rect dstrect, double angle, bint flip) except True:
        ret = SDL_RenderCopyEx(self.renderer, texture.texture, &srcrect.rect, &dstrect.rect, angle, NULL, flip)
        if ret == -1:
            raise SDLError()

    cdef bint render_set_clip_rect(self, Rect rect) except True:
        ret = SDL_RenderSetClipRect(self.renderer, &rect.rect)
        if ret == -1:
            raise SDLError()

    cdef bint render_set_viewport(self, Rect rect) except True:
        ret = SDL_RenderSetViewport(self.renderer, &rect.rect)
        if ret == -1:
            raise SDLError()

    cdef Texture create_texture_from_surface(self, Surface surface):
        texture = Texture()
        texture.texture = SDL_CreateTextureFromSurface(self.renderer, surface.surface)
        if texture.texture == NULL:
            raise SDLError()
        return texture


cdef class Texture:
    cpdef set_color_mod(self, Uint8 r, Uint8 g, Uint8 b):
        ret = SDL_SetTextureColorMod(self.texture, r, g, b)
        if ret == -1:
            raise SDLError()

    cpdef set_alpha_mod(self, Uint8 alpha):
        ret = SDL_SetTextureAlphaMod(self.texture, alpha)
        if ret == -1:
            raise SDLError()

    cpdef set_blend_mode(self, SDL_BlendMode blend_mode):
        ret = SDL_SetTextureBlendMode(self.texture, blend_mode)
        if ret == -1:
            raise SDLError()


cdef class Rect:
    def __init__(self, int x, int y, int w, int h):
        self.rect.x = x
        self.rect.y = y
        self.rect.w = w
        self.rect.h = h


cdef class Color:
    def __init__(self, Uint8 b, Uint8 g, Uint8 r, Uint8 a=255):
        self.color.r = r
        self.color.g = g
        self.color.b = b
        self.color.a = a


cdef class Surface:
    def __dealloc__(self):
        if self.surface != NULL:
            SDL_FreeSurface(self.surface)

    property pixels:
        def __get__(self):
            return bytes(self.surface.pixels[:self.surface.w * self.surface.h * 4])

    cdef bint blit(self, Surface other) except True:
        if SDL_BlitSurface(other.surface, NULL, self.surface, NULL) < 0:
            raise SDLError()

    cdef void set_alpha(self, Surface alpha_surface) nogil:
        nb_pixels = self.surface.w * self.surface.h
        image = self.surface.pixels
        alpha = alpha_surface.surface.pixels

        for i in range(nb_pixels):
            # Only use the red value, assume the others are equal.
            image[3+4*i] = alpha[3*i]


cdef class Music:
    def __dealloc__(self):
        if self.music != NULL:
            Mix_FreeMusic(self.music)

    cdef void play(self, int loops) nogil:
        Mix_PlayMusic(self.music, loops)

    cdef void set_loop_points(self, double start, double end) nogil:
        #Mix_SetLoopPoints(self.music, start, end)
        pass


cdef class Chunk:
    def __dealloc__(self):
        if self.chunk != NULL:
            Mix_FreeChunk(self.chunk)

    cdef void play(self, int channel, int loops) nogil:
        Mix_PlayChannel(channel, self.chunk, loops)

    cdef void set_volume(self, float volume) nogil:
        Mix_VolumeChunk(self.chunk, int(volume * 128))


cdef class Font:
    def __init__(self, str filename, int ptsize):
        path = filename.encode()
        self.font = TTF_OpenFont(path, ptsize)
        if self.font == NULL:
            raise SDLError()

    def __dealloc__(self):
        if self.font != NULL:
            TTF_CloseFont(self.font)

    cdef Surface render(self, unicode text):
        cdef SDL_Color white
        white = SDL_Color(255, 255, 255, 255)
        surface = Surface()
        string = text.encode('utf-8')
        surface.surface = TTF_RenderUTF8_Blended(self.font, string, white)
        if surface.surface == NULL:
            raise SDLError()
        return surface


cdef bint init(Uint32 flags) except True:
    if SDL_Init(flags) < 0:
        raise SDLError()


cdef bint img_init(int flags) except True:
    if IMG_Init(flags) != flags:
        raise SDLError()


cdef bint mix_init(int flags) except True:
    if Mix_Init(flags) != flags:
        raise SDLError()


cdef bint ttf_init() except True:
    if TTF_Init() < 0:
        raise SDLError()


cdef bint gl_set_attribute(SDL_GLattr attr, int value) except True:
    if SDL_GL_SetAttribute(attr, value) < 0:
        raise SDLError()


cdef Surface load_png(file_):
    data = file_.read()
    rwops = SDL_RWFromConstMem(<char*>data, len(data))
    surface = Surface()
    surface.surface = IMG_LoadPNG_RW(rwops)
    SDL_RWclose(rwops)
    if surface.surface == NULL:
        raise SDLError()
    return surface


cdef Surface create_rgb_surface(int width, int height, int depth, Uint32 rmask=0, Uint32 gmask=0, Uint32 bmask=0, Uint32 amask=0):
    surface = Surface()
    surface.surface = SDL_CreateRGBSurface(0, width, height, depth, rmask, gmask, bmask, amask)
    if surface.surface == NULL:
        raise SDLError()
    return surface


cdef bint mix_open_audio(int frequency, Uint16 format_, int channels, int chunksize) except True:
    if Mix_OpenAudio(frequency, format_, channels, chunksize) < 0:
        raise SDLError()


cdef bint mix_allocate_channels(int numchans) except True:
    if Mix_AllocateChannels(numchans) != numchans:
        raise SDLError()


cdef int mix_volume(int channel, float volume) nogil:
    return Mix_Volume(channel, int(volume * 128))


cdef int mix_volume_music(float volume) nogil:
    return Mix_VolumeMusic(int(volume * 128))


cdef Music load_music(str filename):
    music = Music()
    path = filename.encode()
    music.music = Mix_LoadMUS(path)
    if music.music == NULL:
        raise SDLError()
    return music


cdef Chunk load_chunk(file_):
    cdef SDL_RWops *rwops
    chunk = Chunk()
    data = file_.read()
    rwops = SDL_RWFromConstMem(<char*>data, len(data))
    chunk.chunk = Mix_LoadWAV_RW(rwops, 1)
    if chunk.chunk == NULL:
        raise SDLError()
    return chunk


cdef Uint32 get_ticks() nogil:
    return SDL_GetTicks()


cdef void delay(Uint32 ms) nogil:
    SDL_Delay(ms)


cpdef bint show_simple_message_box(unicode message) except True:
    text = message.encode('UTF-8')
    ret = SDL_ShowSimpleMessageBox(1, 'PyTouhou', text, NULL)
    if ret == -1:
        raise SDLError()
