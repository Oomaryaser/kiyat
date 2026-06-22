import { Logger, Inject } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
} from '@nestjs/websockets';
import { JwtService } from '@nestjs/jwt';
import Redis from 'ioredis';
import { Server, Socket } from 'socket.io';
import { TrackingService, VehicleLocationPayload } from './tracking.service';

@WebSocketGateway({ cors: true, namespace: 'tracking' })
export class TrackingGateway implements OnGatewayConnection {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(TrackingGateway.name);

  constructor(
    private readonly tracking: TrackingService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    @Inject('REDIS_CLIENT') private readonly redis: Redis,
  ) {}

  async handleConnection(client: Socket) {
    try {
      const authHeader = client.handshake.auth?.token || client.handshake.headers?.authorization;
      const token = authHeader?.startsWith('Bearer ') ? authHeader.substring(7) : authHeader;
      if (!token) {
        this.logger.warn(`Disconnecting socket client: Missing auth token`);
        client.disconnect();
        return;
      }
      const payload = await this.jwt.verifyAsync(token, {
        secret: this.config.getOrThrow<string>('JWT_SECRET'),
      });
      client.data.user = payload;
      this.logger.log(`Socket client connected and authenticated: ${payload.phone}`);
    } catch (err: any) {
      this.logger.warn(`Disconnecting socket client: Invalid token (${err.message})`);
      client.disconnect();
    }
  }

  private verifyClientToken(client: Socket): any {
    const user = client.data.user;
    if (!user) {
      this.logger.warn(`Unauthorized socket connection`);
      client.disconnect();
      return null;
    }
    const nowInSeconds = Math.floor(Date.now() / 1000);
    if (user.exp && nowInSeconds >= user.exp) {
      this.logger.warn(`Socket client token expired: ${user.phone}`);
      client.disconnect();
      return null;
    }
    return user;
  }

  @SubscribeMessage('vehicle:subscribe')
  handleSubscribe(@MessageBody() body: { routeId: string }, @ConnectedSocket() client: Socket) {
    const user = this.verifyClientToken(client);
    if (!user) return { error: 'Unauthorized' };

    client.join(`route:${body.routeId}`);
    this.logger.log(`Client subscribed to route ${body.routeId}`);
    return { event: 'vehicle:subscribed', routeId: body.routeId };
  }

  @SubscribeMessage('vehicle:location')
  async handleLocation(@MessageBody() body: VehicleLocationPayload, @ConnectedSocket() client: Socket) {
    const user = this.verifyClientToken(client);
    if (!user) return { error: 'Unauthorized' };

    // Prevent spoofing: force operatorId to be the authenticated user's ID
    body.operatorId = user.sub;

    const updated = await this.tracking.updateVehicleLocation(body);
    await this.redis.set(`vehicle:${body.vehicleId}:location`, JSON.stringify(body), 'EX', 300);
    this.server.to(`route:${updated.routeId}`).emit('vehicle:update', {
      vehicleId: body.vehicleId,
      routeId: updated.routeId,
      lat: body.lat,
      lng: body.lng,
      lastSeenAt: updated.lastSeenAt,
    });
    return { event: 'vehicle:updated', vehicleId: body.vehicleId };
  }

  @SubscribeMessage('token:update')
  async handleTokenUpdate(
    @MessageBody() body: { token: string },
    @ConnectedSocket() client: Socket,
  ) {
    try {
      const token = body.token?.startsWith('Bearer ') ? body.token.substring(7) : body.token;
      if (!token) {
        this.logger.warn(`Token update failed: missing token`);
        client.disconnect();
        return { event: 'token:updated', status: 'error', message: 'Missing token' };
      }
      const payload = await this.jwt.verifyAsync(token, {
        secret: this.config.getOrThrow<string>('JWT_SECRET'),
      });
      client.data.user = payload;
      this.logger.log(`Socket client token updated and verified: ${payload.phone}`);
      return { event: 'token:updated', status: 'success' };
    } catch (err: any) {
      this.logger.warn(`Socket client token update failed: ${err.message}`);
      client.disconnect();
      return { event: 'token:updated', status: 'error', message: err.message };
    }
  }
}
