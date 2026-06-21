import { Logger } from '@nestjs/common';
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
  private readonly redis: Redis;

  constructor(
    private readonly tracking: TrackingService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {
    this.redis = new Redis(this.config.get<string>('REDIS_URL', 'redis://localhost:6379'));
  }

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

  @SubscribeMessage('vehicle:subscribe')
  handleSubscribe(@MessageBody() body: { routeId: string }, @ConnectedSocket() client: Socket) {
    client.join(`route:${body.routeId}`);
    this.logger.log(`Client subscribed to route ${body.routeId}`);
    return { event: 'vehicle:subscribed', routeId: body.routeId };
  }

  @SubscribeMessage('vehicle:location')
  async handleLocation(@MessageBody() body: VehicleLocationPayload) {
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
}
